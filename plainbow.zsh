# Plainbow
# by Martin Ohmann
# https://github.com/martinohmann/plainbow
# MIT License
#
# This theme is based on the awesome pure prompt by Sindre Sorhus which can be
# found here: https://github.com/sindresorhus/pure

# For my own and others sanity
# git:
# %b => current branch
# %a => current action (rebase/merge)
# prompt:
# %F => color dict
# %f => reset color
# %~ => current path
# %* => time
# %n => username
# %m => shortname host
# %(?..) => prompt conditional - %(condition.true.false)
# terminal codes:
# \e7   => save cursor position
# \e[2A => move cursor 2 lines up
# \e[1G => go to position 1 in terminal
# \e8   => restore cursor position
# \e[K  => clears everything after the cursor on the current line
# \e[2K => clear everything on the current line

# turns seconds into human readable time
# 165392 => 1d 21h 56m 32s
# https://github.com/sindresorhus/pretty-time-zsh
prompt_plainbow_human_time_to_var() {
	local human=" {" total_seconds=$1 var=$2
	local days=$(( total_seconds / 60 / 60 / 24 ))
	local hours=$(( total_seconds / 60 / 60 % 24 ))
	local minutes=$(( total_seconds / 60 % 60 ))
	local seconds=$(( total_seconds % 60 ))
	(( days > 0 )) && human+="${days}d "
	(( hours > 0 )) && human+="${hours}h "
	(( minutes > 0 )) && human+="${minutes}m "
	human+="${seconds}s}"

	# store human readable time in variable as specified by caller
	typeset -g "${var}"="${human}"
}

# stores (into prompt_plainbow_cmd_exec_time) the exec time of the last command
# if set threshold was exceeded
prompt_plainbow_check_cmd_exec_time() {
	integer elapsed
	(( elapsed = EPOCHSECONDS - ${prompt_plainbow_cmd_timestamp:-$EPOCHSECONDS} ))
	prompt_plainbow_cmd_exec_time=
	(( elapsed > ${PLAINBOW_CMD_MAX_EXEC_TIME:=5} )) && {
		prompt_plainbow_human_time_to_var $elapsed "prompt_plainbow_cmd_exec_time"
	}
}

prompt_plainbow_clear_screen() {
	# enable output to terminal
	zle -I
	# clear screen and move cursor to (0, 0)
	print -n '\e[2J\e[0;0H'
	# reset command count to zero so we don't start with a blank line
	plainbow_prompt_command_count=0
	# print preprompt
	prompt_plainbow_preprompt_render precmd
}

prompt_plainbow_set_title() {
	# emacs terminal does not support settings the title
	(( ${+EMACS} )) && return

	case $TTY in
		# Don't set title over serial console.
		/dev/ttyS[0-9]*) return;;
	esac

	# tell the terminal we are setting the title
	print -n '\e]0;'
	# show hostname if connected through ssh
	[[ -n $SSH_CONNECTION ]] && print -Pn '(%m) '
	case $1 in
		expand-prompt)
			print -Pn $2;;
		ignore-escape)
			print -rn $2;;
	esac
	# end set title
	print -n '\a'
}

prompt_plainbow_preexec() {
    # reset command count to that terminal window does not start with a newline
    # after clear
    [[ $2 == clear ]] && plainbow_prompt_command_count=0

    # attempt to detect and prevent prompt_plainbow_async_git_fetch from
    # interfering with user initiated git or hub fetch
	[[ $2 =~ (git|hub)\ .*(pull|fetch) ]] && async_flush_jobs 'prompt_plainbow'

	typeset -g prompt_plainbow_cmd_timestamp=$EPOCHSECONDS

    # shows the current dir and executed command in the title while a process
    # is active
	prompt_plainbow_set_title 'ignore-escape' "$PWD:t: $2"

	# Disallow python virtualenv from updating the prompt, set it to 12 if
	# untouched by the user to indicate that plainbow modified it. Here we use
	# magic number 12, same as in psvar.
	export VIRTUAL_ENV_DISABLE_PROMPT=${VIRTUAL_ENV_DISABLE_PROMPT:-12}
}

prompt_plainbow_preprompt_render() {
	# store the current prompt_subst setting so that it can be restored later
	local cwd_style prompt_subst_status=$options[prompt_subst]

	# make sure prompt_subst is unset to prevent parameter expansion in preprompt
	setopt local_options no_prompt_subst

    # check that no command is currently running, the preprompt will otherwise
    # be rendered in the wrong place
	[[ -n ${prompt_plainbow_cmd_timestamp+x} && "$1" != "precmd" ]] && return

	# construct preprompt
	local preprompt=""

	# add a newline between commands if it is not the first command
    if [[ "$plainbow_prompt_command_count" -gt 1 ]]; then
        preprompt+=$'\n'
    fi

	local symbol_color="%(?.green.red)"

	# show virtual env
	preprompt+="%(12V.%F{242}%12v%f .)"

    # current working directory style
    if (( ${PLAINBOW_FULL_CWD:-1} )); then
        cwd_style="%~"
    else
        cwd_style="%c"
    fi

	# username and machine if applicable
	# preprompt+=$prompt_plainbow_username

	# directory, colored by vim status
    preprompt+="%F{blue}${cwd_style}%f"

	# git info
	preprompt+="%F{red}${vcs_info_msg_0_}%f"
	preprompt+="%F{yellow}${prompt_plainbow_git_dirty}%f"

	# git pull/push arrows
	preprompt+="%F{cyan}${prompt_plainbow_git_arrows}%f"

	# execution time
	preprompt+="%F{240}${prompt_plainbow_cmd_exec_time}%f"

    # background job count
	preprompt+="%F{green}${prompt_plainbow_bg_job_count}%f"

	# prompt symbol, colored by previous command exit code
	preprompt+=" %F{$symbol_color}${PLAINBOW_PROMPT_SYMBOL:-❯}%f "

	# make sure prompt_plainbow_last_preprompt is a global array
	typeset -g -a prompt_plainbow_last_preprompt

	PROMPT="$preprompt"
    RPROMPT="$prompt_plainbow_username"

	# if executing through precmd, do not perform fancy terminal editing
	if [[ "$1" != "precmd" ]]; then
		# only redraw if the expanded preprompt has changed
		[[ "${prompt_plainbow_last_preprompt[2]}" != "${(S%%)preprompt}" ]] || return

		# redraw prompt (also resets cursor position)
		zle && zle .reset-prompt

		setopt no_prompt_subst
	fi

	# store both unexpanded and expanded preprompt for comparison
	prompt_plainbow_last_preprompt=("$preprompt" "${(S%%)preprompt}")
}

prompt_plainbow_precmd() {
	# check exec time and store it in a variable
	prompt_plainbow_check_cmd_exec_time

	# check number for background jobs
	(( ${PLAINBOW_BG_JOBS:-0} )) && prompt_plainbow_bg_job_info

    # by making sure that prompt_plainbow_cmd_timestamp is defined here the async
    # functions are prevented from interfering with the initial preprompt
    # rendering
	prompt_plainbow_cmd_timestamp=

	# shows the full path in the title
	prompt_plainbow_set_title 'expand-prompt' '%~'

	# get vcs info
	vcs_info

	# preform async git dirty check and fetch
	prompt_plainbow_async_tasks

	# Check if we should display the virtual env, we use a sufficiently high
	# index of psvar (12) here to avoid collisions with user defined entries.
	psvar[12]=
	# When VIRTUAL_ENV_DISABLE_PROMPT is empty, it was unset by the user and
	# plainbow should take back control.
	if [[ -n $VIRTUAL_ENV ]] && [[ -z $VIRTUAL_ENV_DISABLE_PROMPT || $VIRTUAL_ENV_DISABLE_PROMPT = 12 ]]; then
		psvar[12]="${VIRTUAL_ENV:t}"
		export VIRTUAL_ENV_DISABLE_PROMPT=12
	fi

	# Increment command counter
    (( plainbow_prompt_command_count++ ))

	# print the preprompt
	prompt_plainbow_preprompt_render precmd

	# remove the prompt_plainbow_cmd_timestamp, indicating that precmd has completed
	unset prompt_plainbow_cmd_timestamp
}

# detect the number of jobs that are put in the background
prompt_plainbow_bg_job_info() {
    local job_count

    job_count=$(jobs -l | wc -l)

    if [[ $job_count -gt 0 ]]; then
        prompt_plainbow_bg_job_count=" ${job_count}"
    else
        prompt_plainbow_bg_job_count=
    fi
}

# fastest possible way to check if repo is dirty
prompt_plainbow_async_git_dirty() {
	setopt localoptions noshwordsplit
	local untracked_dirty=$1 dir=$2

	# use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
	builtin cd -q $dir

	if [[ $untracked_dirty = 0 ]]; then
		command git diff --no-ext-diff --quiet --exit-code
	else
		test -z "$(command git status --porcelain --ignore-submodules -unormal)"
	fi

	return $?
}

prompt_plainbow_async_git_fetch() {
	setopt localoptions noshwordsplit
	# use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
	builtin cd -q $1

	# set GIT_TERMINAL_PROMPT=0 to disable auth prompting for git fetch (git 2.3+)
	export GIT_TERMINAL_PROMPT=0
	# set ssh BachMode to disable all interactive ssh password prompting
	export GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-"ssh -o BatchMode=yes"}

	command git -c gc.auto=0 fetch &>/dev/null || return 1

	# check arrow status after a successful git fetch
	prompt_plainbow_async_git_arrows $1
}

prompt_plainbow_async_git_arrows() {
	setopt localoptions noshwordsplit
	builtin cd -q $1
	command git rev-list --left-right --count HEAD...@'{u}'
}

prompt_plainbow_async_tasks() {
	setopt localoptions noshwordsplit

	# initialize async worker
	((!${prompt_plainbow_async_init:-0})) && {
		async_start_worker "prompt_plainbow" -u -n
		async_register_callback "prompt_plainbow" prompt_plainbow_async_callback
		prompt_plainbow_async_init=1
	}

	# store working_tree without the "x" prefix
	local working_tree="${vcs_info_msg_1_#x}"

	# check if the working tree changed (prompt_plainbow_current_working_tree is prefixed by "x")
	if [[ ${prompt_plainbow_current_working_tree#x} != $working_tree ]]; then
		# stop any running async jobs
		async_flush_jobs "prompt_plainbow"

		# reset git preprompt variables, switching working tree
		unset prompt_plainbow_git_dirty
		unset prompt_plainbow_git_last_dirty_check_timestamp
		prompt_plainbow_git_arrows=

		# set the new working tree and prefix with "x" to prevent the creation of a named path by AUTO_NAME_DIRS
		prompt_plainbow_current_working_tree="x${working_tree}"
	fi

	# only perform tasks inside git working tree
	[[ -n $working_tree ]] || return

	async_job "prompt_plainbow" prompt_plainbow_async_git_arrows $working_tree

	# do not preform git fetch if it is disabled or working_tree == HOME
	if (( ${PLAINBOW_GIT_PULL:-0} )) && [[ $working_tree != $HOME ]]; then
		# tell worker to do a git fetch
		async_job "prompt_plainbow" prompt_plainbow_async_git_fetch $working_tree
	fi

	# if dirty checking is sufficiently fast, tell worker to check it again, or wait for timeout
	integer time_since_last_dirty_check=$(( EPOCHSECONDS - ${prompt_plainbow_git_last_dirty_check_timestamp:-0} ))
	if (( time_since_last_dirty_check > ${PLAINBOW_GIT_DELAY_DIRTY_CHECK:-1800} )); then
		unset prompt_plainbow_git_last_dirty_check_timestamp
		# check check if there is anything to pull
		async_job "prompt_plainbow" prompt_plainbow_async_git_dirty ${PLAINBOW_GIT_UNTRACKED_DIRTY:-0} $working_tree
	fi
}

prompt_plainbow_check_git_arrows() {
	setopt localoptions noshwordsplit
	local arrows left=${1:-0} right=${2:-0}

	(( right > 0 )) && arrows+=${PLAINBOW_GIT_DOWN_ARROW:-⇣}
	(( left > 0 )) && arrows+=${PLAINBOW_GIT_UP_ARROW:-⇡}

	[[ -n $arrows ]] || return
	typeset -g REPLY=" $arrows"
}

prompt_plainbow_async_callback() {
	setopt localoptions noshwordsplit
	local job=$1 code=$2 output=$3 exec_time=$4

	case $job in
		prompt_plainbow_async_git_dirty)
			local prev_dirty=$prompt_plainbow_git_dirty
			if (( code == 0 )); then
				prompt_plainbow_git_dirty=
			else
				prompt_plainbow_git_dirty="${PLAINBOW_GIT_DIRTY_SYMBOL:- }"
			fi

			[[ $prev_dirty != $prompt_plainbow_git_dirty ]] && prompt_plainbow_preprompt_render

            # When prompt_plainbow_git_last_dirty_check_timestamp is set, the
            # git info is displayed in a different color. To distinguish
            # between a "fresh" and a "cached" result, the preprompt is
            # rendered before setting this variable. Thus, only upon next
            # rendering of the preprompt will the result appear in a different
            # color.
			(( $exec_time > 2 )) && prompt_plainbow_git_last_dirty_check_timestamp=$EPOCHSECONDS
			;;
		prompt_plainbow_async_git_fetch|prompt_plainbow_async_git_arrows)
			# prompt_plainbow_async_git_fetch executes prompt_plainbow_async_git_arrows
			# after a successful fetch.
			if (( code == 0 )); then
				local REPLY
				prompt_plainbow_check_git_arrows ${(ps:\t:)output}
				if [[ $prompt_plainbow_git_arrows != $REPLY ]]; then
					prompt_plainbow_git_arrows=$REPLY
					prompt_plainbow_preprompt_render
				fi
			fi
			;;
	esac
}

prompt_plainbow_setup() {
	# prevent percentage showing up if output doesn't end with a newline
	export PROMPT_EOL_MARK=''

	zmodload zsh/datetime
	zmodload zsh/zle
	zmodload zsh/parameter

	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
	autoload -Uz async && async

	add-zsh-hook precmd prompt_plainbow_precmd
	add-zsh-hook preexec prompt_plainbow_preexec

	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:*' use-simple true
	zstyle ':vcs_info:*' max-exports 2
	zstyle ':vcs_info:git*' formats ' %b' 'x%R'
	zstyle ':vcs_info:git*' actionformats ' %b|%a' 'x%R'

	# if the user has not registered a custom zle widget for clear-screen,
	# override the builtin one so that the preprompt is displayed correctly when
	# ^L is issued.
	if [[ $widgets[clear-screen] == 'builtin' ]]; then
		zle -N clear-screen prompt_plainbow_clear_screen
	fi

	# show username@host if logged in through SSH
	[[ "$SSH_CONNECTION" != '' ]] && prompt_plainbow_username='%F{magenta}%n%f%F{242}@%m%f'

	# show username@host if root, with username in white
	[[ $UID -eq 0 ]] && prompt_plainbow_username='%F{red}%n%f%F{242}@%m%f'

    # guard against oh-my-zsh overriding the theme
    unset ZSH_THEME
}

prompt_plainbow_setup "$@"
