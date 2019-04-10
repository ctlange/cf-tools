@echo off
IF "%1"=="" goto usage
goto start

:usage
echo usage: creape-pipeline.bat project-name path-to-git-repository
goto exit

:start
fly -t ci destroy-pipeline --pipeline %1-auto-pipeline -n
fly -t ci set-pipeline --pipeline %1-auto-pipeline --config ci\auto-pipelines.yml -v projectname=%1 -v git_uri=%2
fly -t ci unpause-pipeline --pipeline %1-auto-pipeline
fly -t ci check-resource --resource %1-auto-pipeline/cf-tools-repository

goto exit
:exit
