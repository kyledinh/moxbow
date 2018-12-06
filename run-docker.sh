#!/bin/bash

docker run -it -v $PWD:/usr/src/app -p 8000:8000 kyledinh/elm:18 bash
