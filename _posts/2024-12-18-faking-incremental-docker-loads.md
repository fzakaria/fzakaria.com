---
layout: post
title: Faking incremental Docker loads
date: 2024-12-18 12:21 -0800
excerpt_separator: <!--more-->
---

While [testcontainers](https://testcontainers.com/) have made it simple to run containers for unit & system tests, they are not well suited for [Bazel](https://bazel.build/) as they rely on `docker pull` to hydrate the Docker daemon. The pulls rely on tags which may be rewritten and require input from data (i.e, the images themselves) unknown to Bazel, as well as network access.

<!--more-->

`rules_oci` is a popular Bazel rules library to incorporate Docker (OCI) images into Bazel that can be used to build subsequent images or be passed as depenedencies to targets.

I wrote a small example [https://github.com/fzakaria/bazel-testcontainer-example](https://github.com/fzakaria/bazel-testcontainer-example) that demonstrates how you can _modify_ [testcontainers-java](https://java.testcontainers.org/) to leverage these images by passing in the `tar.gz` of the image as a `data` dependency and explicitly loading it at startup.

```python
java_test(
    name = "TestContainerExampleTest",
    srcs = [
        "TestContainerExampleTest.java",
    ],
    data = [
        ":tarball.tar",
    ],
    env = {"TARBALL_RUNFILE": "$(rlocationpath :tarball.tar)"},
    runtime_deps = [
        "@maven//:org_slf4j_slf4j_simple",
    ],
    deps = [
        "@bazel_tools//tools/java/runfiles",
        "@maven//:org_testcontainers_testcontainers",
    ],
)

tar(
    name = "layer",
    srcs = ["PingService_deploy.jar"],
)

oci_image(
    name = "image",
    base = "@distroless_java",
    entrypoint = [
        "java",
        "-jar",
        "/src/PingService_deploy.jar",
    ],
    tars = [":layer"],
)
```

_Sounds great?_ 🙌 ... _Right?_ 😕

Turns out if your image is moderately large (>2GiB), an individual upload can take a relatively long time (~30s). This can compound if you have multiple concurrent tests each tryin to upload to the Docker daemon such as in the case in Bazel.

There is **no handshaking** or range-read of the compressed stream, meaning you must send the whole compressed image, which must then be uncompressed and validated for Docker to determine it already had the necessary layers present.

We experienced this with our tests either failing or timing out as each concurrent test tried to upload multi-gigabyte images concurrently.

Turns out, this limitation is documented and known:
* [docker/buildx/issues/107](https://github.com/docker/buildx/issues/107)
* [bazel-contrib/rules_oci/issues/454](https://github.com/bazel-contrib/rules_oci/issues/454)
* [moby/moby/issues/44369](https://github.com/moby/moby/issues/44369)

❗ _There exists no API to query the layers the Docker engine has locally_.

For a _quick'n'dirty_ (but effective) workaround I relied on the following before our CI job
```bash
> bazel query "kind(oci_load, //...)" \
    | xargs -n 1 -P 8 -I target bazel run target
```

It would be great if we didn't need any invocation prior to a test; are Bazel users left _holding the bag_ ? 🫂

Don't despair! Turns out we can **fake incrementality** uploads in Docker with a relatively ingenious method. 😭

> Note: I did not invent this solution. There are other existing prior art, namely:
> * [bazelbuild/rules_docker/blob/master/container/incremental_load.sh.tpl](https://github.com/bazelbuild/rules_docker/blob/master/container/incremental_load.sh.tpl)
> * [aspect-build/bazel-examples/blob/main/oci_python_image/hello_world/app_test.py](https://github.com/aspect-build/bazel-examples/blob/main/oci_python_image/hello_world/app_test.py)
> * [datahouse/bazel_buildlib/blob/oss/buildlib/private/docker/src/loadImageToDocker.ts
](https://github.com/datahouse/bazel_buildlib/blob/oss/buildlib/private/docker/src/loadImageToDocker.ts
)

🪄 The trick is that we will upload Docker images with **metadata but no actual layer data**, and incrementally include the layer only if it's required.

![Piccard graphic](/assets/images/piccard_docker_image.jpg)

Let's break it down.

1. A Docker image, which is different than the OCI format, is a _tar_ file (or _tar.gz_) with a file `manifest.json` that dictates the files that should be present within the archive.

    I've shortened the sha256 in the below example.

    ```json
    [{
    "Config": "blobs/sha256/8f73f04",
    "RepoTags": [ "example:0.1" ],
    "Layers": [
      "blobs/sha256/6dd6992",
      "blobs/sha256/41e9df2",
      "blobs/sha256/3ec46cfe",
      "blobs/sha256/1225e888",
    ]}]
    ```

2. Although our metadata outlines _4 different layers_, we can omit the actual layer data.

    ```bash
    > tar tf testimage.tar.gz | tree --fromfile .
    .
    ├── blobs
    │   └── sha256
    │       └── 8f73f04
    └── manifest.json
    ```


3. If we try to upload this image, if the local daemon has all the layers already present, the upload will succeed **despite us not including any actual layers**.


    ```bash
    > docker load < testimage.tar.gz
    Loaded image: example:0.1
    ```

4. If a layer is missing locally, we detect it via the error response and subsequently include it in
the archive and re-upload it.

    ```bash
    > docker load < testimage.tar.gz
    open /var/lib/docker/tmp/docker-import-2494045611/blobs/sha256/6dd6992:
    no such file or directory
    ```

We can perform these steps incrementally by adding each layer one-at-a-time which looks like the following
in pseudocode.

> ⚠️ It's important to also restrict the `diff_ids` which represent a validation of the state of the container
> when the layers are applied.

```python
function incremental_load(client, repo_tag, base_path):
"""Incrementally loads a Docker image."""

# Parse image index
index_path = base_path + "/index.json"
index = from_json(index_path)

# Parse manifest and config
manifest_digest = index.manifests[0].digest
manifest = from_json(blob(base_path, manifest_digest))
full_config = from_json(blob(base_path, manifest.config.digest))
config_blob_path = blob_path(manifest.config)

missing_layer = null
i = 0
while i < len(manifest.layers):
  # Try uploading each layer one at a time
  layers = manifest.layers[0:i + 1]

  # Create partial config
  tmp_config = full_config.clone().rootfs.diffIds[0:i + 1]

  # Create partial image tar
  image = create_image_tar(base_path, config_blob_path,
                           tmp_config, layers, missing_layer)

  # Upload partial image, and parse out if any layer is needed
  missing_layer = upload_image(client, image)

  # No missing layer, move onto the next one
  if missing_layer is None:
    i = i + 1
  else:
    # Missing layer found, try again but this time upload it!
    pass

# Upload full image
full_image = create_image_tar(base_path, config_blob_path,
                              full_config, manifest.layers)
upload_image(client, full_image)
```

> If you are interested in the equivalent Java code let me know and I can publish it.

With this approach you can now have **incremental Docker uploads**! Huzzah! 🙌🏽

Problem solved? Sorta? Well....not actually. If the images you are uploading contain
individual large layers, perhaps they were squashed, we are back to square one.


Here we see an example image whose single layer is 1.28GiB.
```bash
> docker image history bad_example:0.1 --human \
                    --format 'table {{ "{{ .Size " }}}}' | head
SIZE
0B
0B
7.87kB
0B
1.28GB
0B
0B
0B
0B
```

### Where's time spent?
At this point you have to improve the image by seggregating the data into more multiple layers or continue to upload it outside of the Bazel context.

🕵️ I would like to dive deeper and understand why the uploads completely stall.

The relevant code in Docker [can be found here](https://github.com/moby/moby/blob/0d53725a7f8abb0b75961806da252f31155cb813/image/tarexport/load.go#L33).

Quick benchmarks done on my M3 Pro MacBook demonstrate it takes ~35-45 seconds to gzip a 2GiB file.
```bash
> time docker save bad_example:0.1 | gzip > test.tar.gz
docker save bad_example:0.1  0.49s user 2.49s system 6% cpu 44.843 total
gzip > test.tar.gz  36.72s user 0.48s system 82% cpu 44.842 total
```

Uploading the image seems to take ~15 seconds
```bash
> time docker load < test.tar.gz
75cc828c731c: Loading layer [==================================================>]  102.1MB/102.1MB
20ebbf9559c4: Loading layer [==================================================>]  552.9MB/552.9MB
1049fe83b46b: Loading layer [==================================================>]  10.14MB/10.14MB
b4a5b99cb981: Loading layer [==================================================>]  331.8kB/331.8kB
a9e2a3aa94a5: Loading layer [==================================================>]  39.34MB/39.34MB
93ca7c014948: Loading layer [==================================================>]  6.144kB/6.144kB
71d670ccc47b: Loading layer [==================================================>]  4.608kB/4.608kB
1838b4d29208: Loading layer [==================================================>]  2.048kB/2.048kB
0d9eb9b0c742: Loading layer [==================================================>]   2.56kB/2.56kB
c68e52b834e4: Loading layer [==================================================>]  1.284GB/1.284GB
749f1729f609: Loading layer [==================================================>]   16.9kB/16.9kB
Loaded image: bad_example:0.1
docker load < test.tar.gz  0.38s user 1.62s system 13% cpu 14.565 total
```

That means creating the archive  and uploading it can take ~1 minute of test execution time. This problem seems to compound with multiple archives created and uploaded; more research is needed to know if the bottleneck is the Docker daemon itself (a global lock?) or the I/O of the disk.