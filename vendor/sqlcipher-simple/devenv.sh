
# source this file for some helper commands

# run tests
function rt ()
{
    cabal-dev build && ./dist/build/test/test
}
