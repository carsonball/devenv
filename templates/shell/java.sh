# java
if [ -d "@@BREW_PREFIX@@/opt/openjdk@21" ]; then
  export JAVA_HOME="@@BREW_PREFIX@@/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
  [ -d "$JAVA_HOME" ] || export JAVA_HOME="@@BREW_PREFIX@@/opt/openjdk@21/libexec"
  __devenv_path "@@BREW_PREFIX@@/opt/openjdk@21/bin"
fi
