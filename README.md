# nmesos-k8s

Over the next couple of years some users of [nmesos][]
might decide to move off [Mesos][] and switch to [Kubernetes][].

`nmesos-k8s` is a tool that uses the same configs as nmesos,
but deploys the service to Kubernetes.

## Installing it

### From source

1. Clone the repo
2. Run `make build`
   * **Note**: You need to use `ruby 3.0.0` or higher. You should run
   `gem update --system` first
3. Move `./nmesos-k8s` to a directory on your path
   (e.g. `~/.local/bin`)

### With [asdf][]

First you need to run ...

```
asdf plugin add nmesos-k8s https://github.com/ninesstack/nmesos-k8s
```

Afterwards you can run ...

```
asdf list-all nmeos-k8s
asdf install nmesos-k8s <version>
asdf global nmesos-k8s <version>
```

... to install whatever version(s) you want.

Note: To get/see the latest version(s) you might need to run
`asdf plugin update nmesos-k8s` to _refresh_ the plugin.

Note: For this to work you need to have [gh][] installed.

## Running it

Run the cli with `nmesos-k8s`. It works more less identically to
`nmesos` in terms of the commands and supplied arguments. There are
two notable differences:

1. You must supply `-s` or `--service-file` in front of the service name
1. You must use `--no-dry-run` in the standard way, rather than the
   non-standard `--dry-run false` that `nmesos` uses.
   
Run `nmesos-k8s` to see all available options.

### Commands

* `release` is for both deployment and any other changes that need to
  be made to a service, including scaling
* `delete` will remove the service and all associated resources
* `print` generates the full Kubernetes manifest that would be
  submitted to the API

## Special Settings

There are a few settings that are supported by `nmesos-k8s` that are
specific to K8s. These will not interfere with `nmesos` operation on
Mesos. They are the following:

* `kubernetes_unfreeze`: This can override `deploy_freeze` against a
  Kubernetes cluster. It is used to allow a service that is not
  allowed to be deployed to Mesos to be deployes to K8s anyway. The
  tool *still respects* `deploy_freeze` unless it is overridden in
  this manner. It is *not* in the `k8s` config section so that it can
  sit in the config right next to `deploy_freeze`. This is so that
  humans can try to reason about it.

* `k8s` config section. This supports the following:
   * `namespace`: enables a specific namespace to be used for this service
   * `service_account_name`: sets the service account to a specific account

[asdf]: https://asdf-vm.com
[nmesos]: https://github.com/NinesStack/nmesos
[Mesos]: https://mesos.apache.org
[Kubernetes]: https://kubernetes.io
