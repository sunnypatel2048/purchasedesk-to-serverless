# PurchaseDesk to Serverless: one entry point for the project's commands.
# Later phases add up, down, status, migrate and the rest.

.PHONY: help lint-infra leftovers ruleset image

TFLINT = tflint --config "$(CURDIR)/infra/.tflint.hcl"

help:  ## list the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

lint-infra:  ## terraform fmt, tflint, Checkov and packer validate over infra/ (the same checks CI runs)
	terraform fmt -check -recursive infra
	$(TFLINT) --init
	cd infra && $(TFLINT) --recursive
	checkov --directory infra --framework terraform --compact --quiet
	packer fmt -check -recursive infra/image
	packer init infra/image
	packer validate -syntax-only infra/image

leftovers:  ## list anything this project left running in AWS (uses the current AWS credentials)
	scripts/leftovers.sh

image:  ## build the legacy server's Windows image with Packer and keep only the newest (about an hour; uses the current AWS credentials)
	scripts/build-image.sh

ruleset:  ## apply .github/rulesets/main.json to the GitHub repository (branch protection as code)
	scripts/apply-ruleset.sh
