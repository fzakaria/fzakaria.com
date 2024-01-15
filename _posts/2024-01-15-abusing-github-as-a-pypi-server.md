---
layout: post
title: Abusing GitHub as a PyPI server
date: 2024-01-15 04:02 +0000
excerpt_separator: <!--more-->
---

> I did not discover or invent this trick .

I wanted to make available a Python wheel to some developers but I did not want to publish it on PyPI for a variety of reasons.
1. I am not the original author of the code and I did not want to take credit for it.
2. I wanted to include the git commit hash in the version number which PyPI does not allow.

<!--more-->

The **trick** is pretty simple but leverages two simple facts:
1. For a URL to behave similar to PyPI for `pip` to install a package, it merely must provide an `index.html` file with links to the wheels.
This is the premise of [PEP 503](https://peps.python.org/pep-0503/) which defines the PyPI Simple Repository API.

    ```html
    <!DOCTYPE html>
    <html>
    <body>
        <a href="/frob/">frob</a>
        <a href="/spamspamspam/">spamspamspam</a>
    </body>
    </html>
    ```

2. GitHub Release Page has a view that includes all the links to all assets in the release. For instance for let's consider the [mlir-wheels](https://github.com/makslevental/mlir-wheels) repository that uses this trick. It has a **single** release with over 5,000 "assets", where each asset is a wheel for a different version and particular platform.
    
![mlir-wheels release page](/assets/images/mlir_wheels_github_release.png)

`pip` itself cannot use this page unfortunately, because the hyperlinks are loaded via Javascript.

There is however an _alternative_ page that is a basic HTML view of all the assets.

[https://github.com/makslevental/mlir-wheels/releases/tag/latest](https://github.com/makslevental/mlir-wheels/releases/tag/latest) -> [https://github.com/makslevental/mlir-wheels/releases/expanded_assets/latest](https://github.com/makslevental/mlir-wheels/releases/expanded_assets/latest)
    
![mlir-wheels expanded assets page](/assets/images/mlir_wheels_github_expanded_assets.png)

With this page you can easily use `pip` to install and upgrade the packages.

```console
pip install mlir-python-bindings \
    -f https://github.com/makslevental/mlir-wheels/releases/expanded_assets/latest
```

Happy hosting. 🎉