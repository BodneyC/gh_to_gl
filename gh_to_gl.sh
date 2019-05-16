#!/bin/bash

GL_TOKEN=
GL_USER=
GL_API=
GL_CREDS="./creds"
GL_SERVER="https://gitlab.com"
GH_TOKEN=
GH_USER=
GH_API="https://api.github.com"
WORK_DIR="./working_dir"

function push_branches() {
	MAKE_GL_REPO=$(curl -XPOST -H "Private-Token: $GL_TOKEN" "$GL_API/projects?name=$2")
	GIT_BRANCHES=$(git show-branch --all --list \
		| grep "origin/" \
		| sed '/HEAD/d;s|origin/||' \
		| cut -d'[' -f2 \
		| cut -d']' -f1)
	unset  IFS
	git remote set-url origin "$1"
	for branch in $GIT_BRANCHES; do
		git checkout $branch
		git push origin $branch
	done
}
function handle_gh_url() {
	echo "Repo: $2"
	GL_URL="https://gitlab.com/$GL_USER/$2.git"
	echo "  - Cloning..."
	git clone "$1" > /dev/null 2>&1
	cd "$2"
	GL_PUSH="y"
	if [[ "$MAKE_GL_REPO" =~ "has already been taken" ]]; then
		read -n1 -p "  - Repo name in use, attempt push anyway [yN]?" GL_PUSH
	fi
	[[ "$GL_PUSH" =~ [Yy] ]] &&	push_branches "$GL_URL"
	cd ..
	rm -rf "$2"
}
function setup_gl_creds() {
	cat << EOF >> $GL_CREDS
#!/bin/bash
echo username=$GL_USER
echo password=$GL_TOKEN
EOF
	chmod +x $GL_CREDS
	OLD_HELPER=$(git config --global credential.helper)
	git config --global credential.helper $(realpath $GL_CREDS)
}
function get_gl_repo() {
	GH_URLS=$(curl -s -XGET -H "Authorization: Basic $GH_TOKEN" "$GH_API/users/$GH_USER/repos?per_page=100" \
		| grep '"clone_url"' \
		| sed 's|^.*"\(https://[^"]*\)",|\1|' \
		| sed "s|https://|https://$GH_USER:${GH_TOKEN}@|")
	GH_DIRS=$(sed 's|^.*/\(.*\).git\($\)|\1\2|' <<< $GH_URLS)
	setup_gl_creds
	local IFS=' '
	while read -r -u4 url; read -r -u5 dir; do
		handle_gh_url  "$url" "$dir" 
	done 4<<<"$GH_URLS" 5<<<"$GH_DIRS"
	git config --global credential.helper "$OLD_HELPER"
	rm $GL_CREDS
	rm -r $WORK_DIR
}
function gl_auth() {
	[[ $GL_USER ]] || read -p "Gitlab username: " GL_USER
	if [[ -z $GL_TOKEN ]]; then
		read -p "Gitlab personal access token: " GL_TOKEN
	fi
}
function gh_auth() {
	[[ $GH_USER ]] || read -p "Github username: " GH_USER
	if [[ -z $GH_TOKEN ]]; then
		read -sp "Github password/token: " GH_TOKEN
		echo
	fi
}
function parse_args() {
	while [[ "$#" > 0 ]]; do
		arg="$1"
		case $arg in
			--gl-user)
				GL_USER="$2"
				shift; shift ;;
			--gl-token)
				GL_TOKEN="$2"
				shift; shift ;;
			--gh-user)
				GH_USER="$2"
				shift; shift ;;
			--gh-token)
				GH_TOKEN="$2"
				shift; shift ;;
			--gl-server)
				GL_SERVER="$2"
				shift; shift ;;
			--gl-cred-file)
				GL_CREDS="$(realpath $2)"
				shift; shift ;;
			*)
				echo "Unknown option: $arg"
				exit -1
		esac
		GL_API="$GL_SERVER/api/v4"
	done
}
function main() {
	mkdir -p $WORK_DIR && cd $WORK_DIR
	parse_args "$@"
	gh_auth
	gl_auth
	get_gl_repo
}
main "$@"
