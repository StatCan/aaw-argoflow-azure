# NOTE: Before using this makefile, you will need to use
# the python scripts to generate the distribution folder and the
# secrets. See the README

# Config
SETUP_CONF_PATH = setup.env

# Helpers
REPLACE := .helpers/replace.py -c $(SETUP_CONF_PATH)
KUBE_TEMPLATE := kubectl create --dry-run=client -o yaml

# Directories
TEMPLATE := template
DISTRIBUTION := distribution

GENERATED := secrets/generated
VAULT := secrets/vault
SEALED := secrets/sealed


SECRETS := $(GENERATED) $(EXTERNAL) $(SEALED)

CHROMIUM := chromium --incognito
# CHROMIUM := flatpak run org.chromium.Chromium --incognito

# Kind
KIND_NAME := argoflow

# Handy
OKBLUE := '\033[94m'
OKCYAN := '\033[96m'
OKGREEN := '\033[92m'
WARNING := '\033[93m'
FAIL := '\033[91m'
ENDC := '\033[0m'
BOLD := '\033[1m'

#===========================================


.DEFAULT: all
.PHONY: all clean kind $(SECRETS)


##########################################
###   ____                     _
###  / ___|  ___  ___ _ __ ___| |_ ___
###  \___ \ / _ \/ __| '__/ _ \ __/ __|
###   ___) |  __/ (__| | |  __/ |_\__ \
###  |____/ \___|\___|_|  \___|\__|___/
###
###

kubeseal:
	kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.16.0/controller.yaml

$(SECRETS):
	@printf $(WARNING)
	@printf $(BOLD)
	@echo "Unpacking $@ into the distribution folder (as symlinks)"
	@printf $(ENDC)
	if test $$(basename $@) = sealed; then \
		$(MAKE) kubeseal; \
	fi
	stow -S $$(basename $@) -d $$(dirname $@) -t $(DISTRIBUTION)


##############################################
###   ___  ___     _        _ _    ______
###   |  \/  |    | |      | | |   | ___ \.
###   | .  . | ___| |_ __ _| | |   | |_/ /
###   | |\/| |/ _ \ __/ _` | | |   | ___ \.
###   | |  | |  __/ |_ (_| | | |____ |_/ /
###   \_|  |_/\___|\__\__,_|_\_____\____/
###

METALLB_CONFIGMAP := kind/metallb/configmap.yaml

# # My VS-Code breaks syntax highlighting here, but I think that's VS-Code's fault.
# export metallb_configmap := $(METALLB_CONFIGMAP)
#
# # Note, this only provides 10 IPs
# define METALLB_CONFIGMAP_PATCHER =
# import yaml
# import sys
#
# config_map = sys.argv[1]
# cidr = sys.argv[2]
#
# with open(config_map) as f:
#     data = yaml.safe_load(f.read())
#
# data["data"]["config"] = yaml.safe_load(data["data"]["config"])
# second_cidr = cidr.split(".")
# second_cidr[-1] = str(int(second_cidr[-1]) + 10)
# second_cidr = '.'.join(second_cidr)
#
# data["data"]["config"]["address-pools"][0]["addresses"][0] = f"{cidr}-{second_cidr}"
# data["data"]["config"] = yaml.dump(data["data"]["config"])
#
# print(yaml.dump(data))
# endef
# export METALLB_CONFIGMAP_PATCHY = $(value METALLB_CONFIGMAP_PATCHER)
#
# test-metallb:
# 	@python3 -c "$$METALLB_CONFIGMAP_PATCHY" $(METALLB_CONFIGMAP) $$METALLB_CIDR


kind/metallb/secret.yaml:
	$(KUBE_TEMPLATE) secret generic -n metallb-system memberlist \
		--from-literal=secretkey="$$(openssl rand -base64 128)" > kind/metallb/secret.yaml

deploy-metallb: kind/metallb/secret.yaml
	# Give ArgoCD a loadbalancer endpoint.
	kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}' || true

	# Make a backup
	[ -f $(METALLB_CONFIGMAP).bak ] || cp $(METALLB_CONFIGMAP) $(METALLB_CONFIGMAP).bak

	# Fix the IP Range of MetalLB
	@printf $(WARNING)
	@printf $(BOLD)
	@echo "Setting the MetalLb address range using your docker network"
	@echo "The old file will be copied to $(METALLB_CONFIGMAP).bak"
	@printf $(ENDC)
	@CIDR=$$(docker network inspect -f '{{.IPAM.Config}}' kind | sed 's~\[{\([0-9/.]*\) .*~\1~'); \
	SUBCLASS=$$(echo $$CIDR | awk -F '.' '{printf("%d.%d",$$1,$$2)}'); \
	METALLB_RANGE=$$(grep '\([0-9][0-9\.]*\)-\([0-9][0-9\.]*\)' $(METALLB_CONFIGMAP)); \
	METALLB_CLASS=$$(echo $$METALLB_RANGE | sed 's/^ *- *//' | awk -F '.' '{printf("%d.%d", $$1, $$2) }'); \
	sed -i "s/$$METALLB_CLASS/$$SUBCLASS/g" $(METALLB_CONFIGMAP)

	kustomize build kind/metallb | kubectl apply -f -


##############################################
###
###          d8888   888       888
###         d88888   888       888
###        d88P888   888       888
###       d88P 888   888       888
###      d88P  888   888       888
###     d88P   888   888       888
###    d8888888888   888       888
###   d88P     888   88888888  88888888
###
###


define METRICS_SERVER_PATCH
{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "metrics-server",
            "args": [
              "--cert-dir=/tmp",
              "--secure-port=4443",
              "--kubelet-insecure-tls",
              "--kubelet-preferred-address-types=InternalIP"
            ]
          }
        ]
      }
    }
  }
}
endef
METRICS_SERVER_PATCH := $(shell echo '$(METRICS_SERVER_PATCH)' | jq -c)

clean: delete
	rm -rf $(DISTRIBUTION)

delete:
	kind delete clusters $(KIND_NAME)

kind:
	kind create cluster --name $(KIND_NAME) --config kind/kind-cluster.yaml
	kubectl cluster-info --context kind-$(KIND_NAME)
	kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.3.6/components.yaml
	kubectl patch deployment metrics-server -n kube-system -p '$(METRICS_SERVER_PATCH)'


### Local git server,
### For private ArgoCD in kind
gitserver:
	docker build . -t gitserver:latest -f kind/gitserver.Dockerfile
	kind load docker-image gitserver:latest --name $(KIND_NAME)

	kubectl create namespace git || true
	kubectl apply -f kind/gitserver/Deployment.yaml
	kubectl apply -f kind/gitserver/Service.yaml
	kubectl rollout restart deployment -n git gitserver

	# Give a little grace period before going to the next steps
	sleep 30


deploy-argocd: $(DISTRIBUTION)
	kustomize build $(DISTRIBUTION)/argocd/base/ | kubectl apply -f -

	@while ! kubectl get secrets \
		-n argocd | grep -q argocd-initial-admin-secret; do \
		echo "Waiting for ArgoCD to start..."; \
		sleep 5; \
	done

	$(MAKE) argo-get-pass

argo-get-pass:
	@printf $(OKGREEN)
	@printf $(BOLD)
	@echo "ArgoCD Login"
	@echo "=========================="
	@echo "ArgoCD Username is: admin"
	@printf "ArgoCD Password is: %s\n" $$(kubectl -n argocd \
		get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d)
	@echo "=========================="
	@printf $(ENDC)


get-etc-hosts:
	@printf $(OKGREEN)
	@printf $(BOLD)
	@echo '# Add this to your hosts'
	@kubectl get svc --all-namespaces -o json | \
		jq -cr '.items[] | select(.status.loadBalancer != {})' | \
		jq -cr '@text "\(.status.loadBalancer.ingress[0].ip)\t<\(.metadata.name)>.example.com"'
	@printf $(ENDC)

deploy-kubeflow: $(DISTRIBUTION)
	kubectl apply -f $(DISTRIBUTION)/kubeflow.yaml

kubeflow-images:
	az acr login --name k8scc01covidacr
	yq e '.spawnerFormDefaults.image.options[]' \
		distribution/kubeflow/notebooks/jupyter-web-app/configs/spawner_ui_config.yaml \
		| xargs -I{} docker pull {} || true
	yq e '.spawnerFormDefaults.image.options[]' \
		distribution/kubeflow/notebooks/jupyter-web-app/configs/spawner_ui_config.yaml \
		| xargs -I{} kind load docker-image {} --name $(KIND_NAME) || true

custom-images:
	az acr login --name k8scc01covidacr
	grep -v '^ *#' kind/custom-images | xargs -I{} docker pull {} || true
	grep -v '^ *#' kind/custom-images | xargs -I{} kind load docker-image {} --name $(KIND_NAME) || true

deploy: kind gitserver deploy-argocd deploy-kubeflow deploy-metallb
	sleep 30
	@while kubectl get svc --all-namespaces | grep -q '<pending>'; do \
		echo "Waiting for LoadBalancers to get IPs assigned..."; \
		sleep 30; \
	done
	$(MAKE) get-etc-hosts


chromium:
	@printf $(WARNING)
	@printf $(BOLD)
	@echo "Make sure you have closed all your previous chromium windows!"
	@printf $(ENDC)
	$(CHROMIUM) --host-rules="MAP *.aaw.cloud.statcan.ca $$(kubectl get svc -n istio-system istio-ingressgateway -o json | jq -r '.status | .. | .ip? // empty')" &
	#kubectl port-forward -n istio-system svc/istio-ingressgateway 8443:80
