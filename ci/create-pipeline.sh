#!/bin/sh

set -e

#see https://blog.osones.com/en/multi-git-branches-workflow-with-concourse-ci.html
#see https://github.com/vito/git-branches-resource

FLY_CMD=fly3

$FLY_CMD login -t ci -c $FLY_CONCOURSE_URL -n $FLY_TEAM -u $FLY_USERNAME -p $FLY_PASSWORD
$FLY_CMD -t ci sync

GIT_FULL_URI=${GIT_URI/https:\/\//https:\/\/$GIT_USERNAME:$GIT_PASSWORD@}

echo git clone $GIT_FULL_URI source-repository
git clone $GIT_FULL_URI source-repository

if [ "$1" = "create" ]
then
	cd source-repository
	NEW_VERSIONS=$(git branch -a | grep remotes/origin | grep -v -F -- "->")
	NEW_VERSIONS=${NEW_VERSIONS//remotes\/origin\//}
	OLD_VERSIONS=
	cd ..
fi

aws configure set aws_access_key_id $S3_ACCESSKEYID
aws configure set aws_secret_access_key $S3_SECRETACCESSKEY
aws configure set region $S3_REGIONNAME

if [ "$1" = "destroy" ]
then
	OLD_PIPELINES=$($FLY_CMD -t ci pipelines | grep $PROJECTNAME | grep -v $PROJECTNAME-auto-pipeline | sed -e 's/  *.*//g')
	for pipe_name in $OLD_PIPELINES; do
		echo "Delete pipeline $pipe_name"
		$FLY_CMD -t ci destroy-pipeline --pipeline $pipe_name -n || true
		aws s3 rm s3://$S3_BUCKET/build/$pipe_name.tar.bz2 || true
	done
	aws s3 ls s3://$S3_BUCKET --recursive
	exit
fi

if [ "$1" = "" ]
then
	export NEW_VERSIONS=$(cat branches/branches)
	export OLD_VERSIONS=$(cat branches/removed)
	FOUND_MASTER=0

	for version in $NEW_VERSIONS; do
		if [ "$version" = "master" ]
		then
			FOUND_MASTER=1
		fi
	done

	for version in $OLD_VERSIONS; do
		if [ "$version" = "master" ]
		then
			FOUND_MASTER=0
		fi
	done

	if [ "$FOUND_MASTER" = "0" ]
	then
		echo never delete master branch
		exit 1
	fi
fi

for version in $NEW_VERSIONS; do
  pipe_name=${version//\//-}

  cd source-repository
  git reset --hard
  git clean -fd
  git checkout $version
  cd ..

  if [ -e source-repository/ci/pipeline.yml ]
  then
    mkdir -p source-repository/ci
    echo "git_branch: $version" > source-repository/ci/params.yml
    echo "git_uri: $GIT_URI" >> source-repository/ci/params.yml
    echo "projectname: $PROJECTNAME" >> source-repository/ci/params.yml
    echo "pipe_name: $PROJECTNAME-$pipe_name" >> source-repository/ci/params.yml

    if [ -e source-repository/ci/pipeline-params.yml ]
    then
      cat source-repository/ci/pipeline-params.yml >> source-repository/ci/params.yml
    fi

    OK=0
    $FLY_CMD -t ci set-pipeline --pipeline $PROJECTNAME-$pipe_name --config source-repository/ci/pipeline.yml -l source-repository/ci/params.yml -n && OK=1

    echo "Create pipeline branch $version / $PROJECTNAME-$pipe_name"
    if [ "$OK" = "1" ]; then
  	  echo "Unpause pipeline branch $version / $PROJECTNAME-$pipe_name"
	  $FLY_CMD -t ci unpause-pipeline --pipeline $PROJECTNAME-$pipe_name
    fi 

#    $FLY_CMD -t ci destroy-pipeline --pipeline $PROJECTNAME-$pipe_name -n
  else
    echo no pipeline ignore
  fi
done

for version in $OLD_VERSIONS; do
  pipe_name=${version//\//-}
  echo "Delete pipeline branch $version / $PROJECTNAME-$pipe_name"
  $FLY_CMD -t ci destroy-pipeline --pipeline $PROJECTNAME-$pipe_name -n || true
  aws s3 rm s3://$S3_BUCKET/build/$PROJECTNAME-$pipe_name.tar.bz2 || true
done
