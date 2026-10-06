# kubernetes
alias k=kubectl kx=kubectx kn=kubens
if command -v kubectl >/dev/null 2>&1; then
  if [ "$__devenv_sh" = zsh ]; then
    source <(kubectl completion zsh)
    compdef k=kubectl
  else
    source <(kubectl completion bash)
    complete -o default -F __start_kubectl k
  fi
fi
