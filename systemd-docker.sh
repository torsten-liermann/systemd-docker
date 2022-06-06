#!/bin/bash

function validate_cli_arguments {
	[[ ! -n "$containername" ]] && exit_with_error_message 1 'Missing container name'
	[[ ! -n "$dockerargs" ]] && exit_with_error_message 2 'Missing dockerrun' 
	[[ -n "$waitbeforenotify" && $(expr match "$waitbeforenotify" '^[0-9][0-9]*s$')  -eq 0 ]] && exit_with_error_message 2 'wait-before-notify: only seconds supported'
}

function docker_run {
  containerid=$(docker run ${detach:--d} "${dockerargs[@]}")
  return $?
}

function print_args {
while test $# -gt 0
do
	echo arg $# ':' $1
	shift
done
}

function container_exists {
	local status=$(docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null)
	local rc=$?
	if [[ "$status" == 'exited' ||  "$status" == 'removing' || -z "$status" ]]
	then
		return 1
        else
		return 0
	fi

}

function exit_with_error_message {
  echo "$2" >&2
  exit "$1"
}

function wait_before_notify {
  if [[ -n "$waitbeforenotify" ]]
  then
    local waittime=$((SECOND + $(expr match "$waitbeforenotify" '^\([0-9][0-9]*\)')))
  else
    local waittime=$SECOND
  fi

  while [ $SECONDS -lt $waittime ]; do
	  sleep 1
          container_exists "$containerid" || exit_with_error_message 1 "Container is dead"
	  if [[ -n "$startupprobe" ]]
          then
		systemd-notify --status="Test $startupprobe ..."
		startup_probe "$startupprobe" && return 0
		systemd-notify --status="$startupprobe returns 'not ready'"
          else 
	 	systemd-notify --status ".... no startup probe"
	  fi
  done
  return 0
}

function startup_probe {
  local rc=$(curl -s -L -o /dev/null -w '%{http_code}' "$1")
  if [ "$rc" == "200" ]
  then
	  rc=0
  fi
  return $rc
}

function docker_pid {
  echo .............. $(docker inspect -f '{{.State.Pid}}' "$1")
  return $(docker inspect -f '{{.State.Pid}}' "$1")
}

while test $# -gt 0
do
	case "$1" in
	--wait-before-notify|-w)
		waitbeforenotify="$2"
		shift 2
		;;
	--wait-before-notify=*)
		waitbeforenotify=$(expr match "$1"  '^[^=]*=\(.*\)')
  		shift
		;;
	--startup-probe)
		startupprobe="$2"
		shift 2
		;;
	--startup-probe=*)
		startupprobe=$(expr match "$1"  '^[^=]*=\(.*\)')
  		shift
		;;
	--name)
		containername="$2"
  		shift
		;;
	--name=*)
		containername=$(expr match "$1"  '^[^=]*=\(.*\)')
  		shift
		;;
	-d|-detach|--detach)
		detach=-d
  		shift
		;;
	run) 
		shift
		dockerargs=("${@}")
		;;
	*) 
		shift
		;;
        esac

done

  validate_cli_arguments
  docker_run

  container_exists "$containerid" || exit_with_error_message 1 "Container is dead"

  wait_before_notify 

  if container_exists "$containerid" 
  then
          docker_pid $containerid
	  systemd-notify --ready  --pid $(docker_pid $containerid)
	  exit 0
  else
	  exit 1
  fi

