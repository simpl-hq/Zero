#!/bin/bash

set -e

level=$1
apk_parent_dir=$2
sdk_dir=$3

store_file=$4
store_password=$5
key_alias=$6
key_password=$7

if [ -z "${7}" ]; then echo "You didn't enter all required params:
compress-and-sign-apk.sh level apk_parent_dir sdk_dir store_file store_password key_alias key_password"
fi

cd "$apk_parent_dir"

touch remove_this_file remove_this_FILE
(( $(ls | grep "remove_this" | wc -l)==1 )) && case_insensitive=1 || case_insensitive=0
rm remove_this_file remove_this_FILE 2> /dev/null || true

ORIG_NAMES=( $(echo android*.apk) )
for ORIG_NAME in "${ORIG_NAMES[@]}"; do
    unzip -o -q -d apk $ORIG_NAME
    ORIG_NAME_COPY=$ORIG_NAME-copy
    mv "$ORIG_NAME" "$ORIG_NAME_COPY"

    find apk -type f -exec chmod 644 {} +
    find apk -type d -exec chmod 755 {} +
    find apk -exec touch -h -d '2025-12-01T00:00:00' {} +

    (
        cd apk
        find . -not -path './res/*' -not -name 'resources.arsc' -type f -print0 | sort -z | xargs -0 zip -X -r -q -"$level" ../"$ORIG_NAME"
    )

    if [ $case_insensitive -eq 1 ]; then
        list_of_files=$(unzip -l "$ORIG_NAME_COPY" | grep res/ | sed -e "s|.*res/|res/|" | sort)
        for file in $list_of_files; do
            unzip -o -q -d apk "$ORIG_NAME_COPY" "$file"
            (
                cd apk
                chmod 644 "$file"
                touch -h -d '2025-12-01T00:00:00' "$file"
                zip -X -r -q -0 ../"$ORIG_NAME" "$file"
            )
        done
    else
        (
            cd apk
            find res -type f -print0 | sort -z | xargs -0 zip -X -r -q -0 ../"$ORIG_NAME"
        )
    fi

    (
        cd apk
        find resources.arsc -type f -print0 | sort -z | xargs -0 zip -X -r -q -0 ../"$ORIG_NAME"
    )

    ALL_TOOLS=("$sdk_dir"/build-tools/*/)
    BIN_DIR="${ALL_TOOLS[${#ALL_TOOLS[@]}-1]}"

    "$BIN_DIR"/zipalign -p -f 4 "$ORIG_NAME" "$ORIG_NAME"-2

    mv "$ORIG_NAME"{-2,}

    "$BIN_DIR"/apksigner sign \
      --ks "$store_file" --ks-key-alias "$key_alias" --ks-pass "pass:$store_password" \
      --key-pass "pass:$key_password" "$ORIG_NAME"

    rm "$ORIG_NAME_COPY" 2> /dev/null || true
    rm -rf apk || true
    rm "${ORIG_NAME}".idsig 2> /dev/null || true
done
