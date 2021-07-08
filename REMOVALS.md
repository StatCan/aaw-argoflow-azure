Can delete this text file later. Have removals with justification (at least the best I can) here
If I found a non-defunct referencec in our repository that was familiar I kept it.

There are a few "pick one" options in kustomization.yaml that we could delete.



# Template
## argocd-applications Folder
Removed rook-ceph.yaml
Removed xgboost-operator.yaml : don't seem to use (anymore, maybe in the past I found some issues)
Removed experimental*.yaml
Removed loki-stack.yaml

Everything else in here seems necessary (idk about cloudflare-secrets though)


## rook-ceph folder
Could not find any reference in our organization. Removed in entirety
Seems to be a storage solution but we have MinIO

## monitoring-resources

### nvidia-dcgm* 
Don't think we make use of this functionality at the moment.

## kustomization.yaml (.yamls)
Removed rook-ceph
Removed xgboost
Removed loki-stack


## kubeflow/notebooks folder
experimental-* --> removed

# Things I found but never heard of (so keeping)
mpi-operator, mxnet-operator (kubeflow-manifest)