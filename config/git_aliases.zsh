alias ga="git add"
alias gaa="git add --all"
alias gb="git branch"
alias gba="git branch -a"
alias gc="git commit"
alias gca="git commit --amend"
alias gcm="git commit -m"
alias gco="git checkout"
alias gd="git diff"
alias gl="git log --oneline"
alias glog="git log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%C(bold blue)<%an>%Creset' --abbrev-commit"
alias gm="git merge"
alias gp="git push"
alias gpl="git pull"
alias gs="git status"

# Gerrit
gpg() {
    if [ -z "$1" ]; then
        BRANCH_NAME="$(git for-each-ref --format='%(upstream:short)' "$(git symbolic-ref -q HEAD)" | cut -d '/' -f2)"
    else
        BRANCH_NAME="$1"
    fi
    git push origin HEAD:refs/for/$BRANCH_NAME
}

gpgwip() {
    if [ -z "$1" ]; then
        BRANCH_NAME="$(git for-each-ref --format='%(upstream:short)' "$(git symbolic-ref -q HEAD)" | cut -d '/' -f2)"
    else
        BRANCH_NAME="$1"
    fi
    git push origin HEAD:refs/for/$BRANCH_NAME%wip
}

gpgready() {
    if [ -z "$1" ]; then
        BRANCH_NAME="$(git for-each-ref --format='%(upstream:short)' "$(git symbolic-ref -q HEAD)" | cut -d '/' -f2)"
    else
        BRANCH_NAME="$1"
    fi
    git commit --amend --no-edit
    git push origin HEAD:refs/for/$BRANCH_NAME%ready
}
