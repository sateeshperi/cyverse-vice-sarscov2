export TERM=xterm
export LANG=en_US.UTF-8
export SHLVL=1
export OLDPWD=/root
export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true

# Initialize pyenv
export PYENV_ROOT=/usr/local/src/pangolin/.pyenv
export PATH="/usr/local/src/pangolin/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/root/.pyenv/versions/miniconda3-4.7.12/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/root/.pyenv/versions/miniconda3-4.7.12/etc/profile.d/conda.sh" ]; then
        . "/root/.pyenv/versions/miniconda3-4.7.12/etc/profile.d/conda.sh"
    else
        export PATH="/root/.pyenv/versions/miniconda3-4.7.12/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<
