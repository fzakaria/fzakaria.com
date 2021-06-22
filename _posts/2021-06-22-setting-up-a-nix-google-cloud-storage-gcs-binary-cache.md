---
layout: post
title: setting up a Nix Google Cloud Storage (GCS) binary cache
date: 2021-06-22 08:26 -0700
excerpt_separator: <!--more-->
---

A previous post documented how to [setup a binary cache directly on S3]({% post_url 2020-07-15-setting-up-a-nix-s3-binary-cache %}).
Many however are tied to a different public IaaS offering and may not be able to leverage the native S3 integration Nix offers.
Luckily for those using GCP, Google's blob storage equivalent [Google Cloud Storage (GCS)](https://cloud.google.com/storage) has [interoperability](https://cloud.google.com/storage/docs/interoperability) with the S3 API.

This will allow us to host our binary cache on GCS while still using the native S3 integration in Nix.
Following this guide will allow Nix to leverage GCS without having to use a proxy such as [nix-store-gcs-proxy](https://github.com/tweag/nix-store-gcs-proxy).

<!--more-->

> The following guide will assume _some familiarity_ with the GCP ecosystem.
> You may want to follow best practices for reducing IAM roles and service account management.

1. Let's create a bucket for us to store the Nix binary artifacts.
    ```bash
    ❯ gsutil mb gs://nix-cache-testing
    Creating gs://nix-cache-testing/...
    # Validate it exists
    ❯ gsutil du -s gs://nix-cache-testing
    0            gs://nix-cache-testing
    ```
2. Create a _service account_.
    ```bash
    ❯ gcloud iam service-accounts create nix-cache-testing \
    >       --description="Service account for Nix GCS cache" \
    >       --display-name="Nix GCS Service Account"
    Created service account [nix-cache-testing].
    # Validate it exists
    ❯ gcloud iam service-accounts list
    DISPLAY NAME                            EMAIL                                                                     DISABLED
    Nix GCS Service Account                 nix-cache-testing@my-project.google.com.iam.gserviceaccount.com  False
    ```
3. Create an _hmac_ for use with S3 API.
    ```bash
    ❯ gsutil hmac create  nix-cache-testing@my-project.iam.gserviceaccount.com
    Access ID:   GOOGTS7C7FUP3AIRVJTE2BCDKINBTES3HC2GY5CBFJDCQ2SYHV6A6XXVTJFSA
    Secret:      <SCRUBBED OUT FOR SECURITY>
    ```
4. Attach an appropriate IAM role to the service account.
    ```bash
    ❯ gcloud projects add-iam-policy-binding my-project \
        --member="serviceAccount:nix-cache-testing@my-project.iam.gserviceaccount.com" \
        --role="roles/storage.admin" --condition=None
    ```
5. Set the credentials anywhere the [that works](https://docs.aws.amazon.com/cli/latest/topic/config-vars.html#credentials) for the AWS CLI.
   I've chosen to do it in the `~/.aws/credentials` within a profile named _gcp_.
    ```bash
    ❯ cat ~/.aws/credentials
    [gcp]
    aws_access_key_id = GOOGTS7C7FUP3AIRVJTE2BCDKINBTES3HC2GY5CBFJDCQ2SYHV6A6XXVTJFSA
    aws_secret_access_key = <SCRUBBED OUT FOR SECURITY>
    ```
6. Try the _aws_ CLI and validate everything works.

   > You can avoid setting the endpoint-url if you use the [awscli-plugin-endpoint](https://github.com/wbingli/awscli-plugin-endpoint).

    ```bash
    ❯ aws s3 ls --profile gcp --endpoint-url https://storage.googleapis.com
    2021-06-22 09:04:24 nix-cache-testing
    ```

🙌 Woohoo! We've just setup basic interoperability for GCS behaving like the S3 API.
Let's see if the interopt is good enough to fool the API Nix relies on.

Let's create a really basic derivation (_lolhello.nix_) we will be using to test.

> For brevity, I'm not pinning my _nixpkgs_ channel, but that practice is recommended.

```nix
{ pkgs ? import <nixpkgs> { }, stdenv ? pkgs.stdenv, fetchurl ? pkgs.fetchurl }:
stdenv.mkDerivation {
  name = "lolhello";

  src = fetchurl {
    url = "mirror://gnu/hello/hello-2.3.tar.bz2";
    sha256 = "0c7vijq8y68bpr7g6dh1gny0bff8qq81vnp4ch8pjzvg56wb3js1";
  };

  patchPhase = ''
    sed -i 's/Hello, world!/hello, Nix!/g' src/hello.c
  '';
}

```

Let's build it. 🏗️

```bash
❯ nix-build lolhello.nix --no-out-link
/nix/store/czf8l5nlp2kaag96hb42qvqd85glr8f8-lolhello
```

Now let's try to upload it to our GCS bucket via the S3 integration in Nix.

```bash
❯ nix copy $(nix-build lolhello.nix --no-out-link) \
    --to "s3://nix-cache-testing?endpoint=https://storage.googleapis.com&profile=gcp"

# Check it's been uploaded
❯ aws s3 ls nix-cache-testing --profile=gcp --endpoint-url https://storage.googleapis.com
                           PRE nar/
2021-06-22 12:09:42        476 czf8l5nlp2kaag96hb42qvqd85glr8f8.narinfo

# Check it using the gsutil also
❯ gsutil ls gs://nix-cache-testing
gs://nix-cache-testing/czf8l5nlp2kaag96hb42qvqd85glr8f8.narinfo
gs://nix-cache-testing/nar/
```

Now let's delete it from our system.
```bash
❯ nix-store --delete /nix/store/czf8l5nlp2kaag96hb42qvqd85glr8f8-lolhello
```

Now let's try to build it, using our substituter.
We will also disable building locally to verify everything is working correctly.

> I disabled verifying the signatures for now for simplicity of the demo. Please see my
> [previous post]({% post_url 2020-07-15-setting-up-a-nix-s3-binary-cache %}) on how to add signatures.

```bash
❯ nix-build lolhello.nix --no-out-link --builders '' -j0 \
    --option substituters "s3://nix-cache-testing?endpoint=https://storage.googleapis.com&profile=gcp" \
    --option require-sigs false
these paths will be fetched (0.03 MiB download, 0.18 MiB unpacked):
  /nix/store/czf8l5nlp2kaag96hb42qvqd85glr8f8-lolhello
copying path '/nix/store/czf8l5nlp2kaag96hb42qvqd85glr8f8-lolhello' from 's3://nix-cache-testing'...
/nix/store/czf8l5nlp2kaag96hb42qvqd85glr8f8-lolhello
```

🎉 Nice! That was surprisingly straightforward to setup GCS as our Nix binary cache pretending to be S3.

### Addendum

Originally I spent quite a while trying the demo above with a different demo derivation that used a _trivial builder_.
```nix
let pkgs = import <nixpkgs> {};
in
pkgs.writeShellScriptBin "ping"
''
echo "pong"
''
```

I could not figure out why it was not substituting from my binary cache though! 😫
Turns out that some of the [trivial builders](https://github.com/NixOS/nixpkgs/blob/d26902aef932e80eb772026433af13ce662e7872/pkgs/build-support/trivial-builders.nix#L16) disable realization from a store and prefer locally building.

_That was quite a bit of wasted time investigating..._