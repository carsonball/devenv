-- Managed by devenv (k8s module): Kubernetes schemas for plain manifests.
-- Helm charts get helm-ls from the lang.helm extra.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        yamlls = {
          settings = {
            yaml = {
              schemas = {
                kubernetes = {
                  "k8s/**/*.yaml",
                  "kubernetes/**/*.yaml",
                  "manifests/**/*.yaml",
                  "deploy/**/*.yaml",
                  "*.k8s.yaml",
                },
              },
            },
          },
        },
      },
    },
  },
}
