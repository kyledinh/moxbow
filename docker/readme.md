## Using Docker for builds

To run a container with the Elm and a bind-mount to the current working directory

* `docker pull kyledinh/elm:18`
* `docker run -it -v ${PWD}:/usr/src/app -p 8000:8000 kyledinh/elm:18 bash`

or use `run-docker.sh` in the parent directory

## Reference

* Installing Docker - https://docs.docker.com/install/
* https://hub.docker.com/r/kyledinh/elm/
