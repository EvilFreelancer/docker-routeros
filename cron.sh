#!/bin/bash

# Cron fix
cd "$(dirname $0)"

function getTarballs
{
    curl https://mikrotik.com/download/archive -o - 2>/dev/null | \
        grep -o '<a href=['"'"'"][^"'"'"']*['"'"'"]' | \
        sed -e 's/^<a href=["'"'"']//' -e 's/["'"'"']$//' | \
        grep -i vdi | \
        sed 's:.*/::' | \
        sort -V

    curl https://mikrotik.com/download -o - 2>/dev/null | \
        grep -o '<a href=['"'"'"][^"'"'"']*['"'"'"]' | \
        sed -e 's/^<a href=["'"'"']//' -e 's/["'"'"']$//' | \
        grep -i vdi | \
        sed 's:.*/::' | \
        sort -V
}

function getTag
{
    echo "$1" | sed -r 's/chr\-(.*)\.vdi/\1/gi'
}

function checkTag
{
    git rev-list "$1" 2>/dev/null
}

getTarballs | while read line; do
    tag=`getTag "$line"`
    echo ">>> $line >>> $tag"

    if [ "x$(checkTag "$tag")" == "x" ]
        then

            url="https://download.mikrotik.com/routeros/$tag/chr-$tag.vdi"
            if curl --output /dev/null --silent --head --fail "$url"; then
                echo ">>> URL exists: $url"
                sed -r "s/(ROUTEROS_VERSON=\")(.*)(\")/\1$tag\3/g" -i Dockerfile
                git commit -m "Release of RouterOS changed to $tag" -a
                git push
                git tag "$tag"
                git push --tags
            else
                echo ">>> URL don't exist: $url"
            fi

        else
            echo ">>> Tag $tag has been already created"
    fi

done
