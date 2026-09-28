#!/bin/sh
case "$1" in
    --version)
        printf 'Core:\n  - installed: 1.10.2\n'
        ;;
    stream)
        printf 'first\n'
        read -r reply
        printf 'second: %s\n' "$reply"
        printf 'stderr tail' >&2
        ;;
    args)
        printf '%s\n' "$@"
        ;;
    ls)
        while [ "$#" -gt 0 ]; do
            if [ "$1" = '--project-dir' ]; then
                shift
                project=${1##*/}
            fi
            shift
        done
        printf '{"unique_id":"model.%s.orders","name":"orders","resource_type":"model","package_name":"%s","original_file_path":"models/orders.sql"}\n' "$project" "$project"
        ;;
    test|build)
        printf 'stdout progress\n'
        printf '\033[31mFailure in test not_null_orders (models/properties.yml)\033[0m\n'
        printf 'stderr details\n' >&2
        exit 1
        ;;
    *)
        printf 'command completed\n'
        ;;
esac
