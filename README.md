# Moxbow - Markdown Blogging in Elm

Moxbow a website generator for using markdown files, elm files and templates to create an Elm SPA.

```
 source           |    compile        | output

 /src/pages/       \                  /build/index.html (Elm)
 /src/static/       -> /bin/build  -> /build/static/*.* (png, svg, css)
 /src/template/    /                  /build/template/*.json

```

## Build and run

* To run in a docker container, follow directions in `/docker/readme.md`
* `bin/build` creates `build` directory
* `cd build/` then `http-server` to run in dev
* open `http://127.0.0.1:8080`

<img src="assets/mockingbox-screen.png" width="600" />

## Dev Notes

Based on Xossbow framework, made with [Elm](http://elm-lang.org/) and  [billstclair/elm-html-template](http://package.elm-lang.org/packages/billstclair/elm-html-template/latest).

Moxbow will remove the backend parts to make it a Blogging CMS that will updated by builds.

* Project based on: https://github.com/billstclair/xossbow
* Use Elm 18
