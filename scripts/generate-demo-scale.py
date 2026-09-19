#!/usr/bin/env python3
"""Generate a scaled mock dbt project for benchmarking dbtpal navigation.

Creates a chain of N models (each referencing the previous one), a shared
properties file, two source datasets sharing a table name, and a
consistent mock manifest. No dbt binary is required. Output defaults to
demo/generated/scale/ (gitignored); see demo/README.md.
"""

import argparse
import json
import os
import shutil
import sys


def write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--models", type=int, default=500)
    parser.add_argument("--out", default="demo/generated/scale")
    args = parser.parse_args()
    if args.models < 2:
        sys.exit("--models must be at least 2")

    root = os.path.abspath(args.out)
    if os.path.isdir(root):
        shutil.rmtree(root)

    write(os.path.join(root, "dbt_project.yml"), "name: 'scale'\nconfig-version: 2\n")
    write(os.path.join(root, "models", "m_00000.sql"), "select * from {{ source('d0', 't_shared') }}\n")
    for i in range(1, args.models):
        write(
            os.path.join(root, "models", "m_%05d.sql" % i),
            "select * from {{ ref('m_%05d') }}\n" % (i - 1),
        )

    schema = ["version: 2", "", "models:"]
    for i in range(args.models):
        schema += ["  - name: m_%05d" % i, "    columns:", "      - name: id"]
    write(os.path.join(root, "models", "schema.yml"), "\n".join(schema) + "\n")

    write(
        os.path.join(root, "dataset", "d0.yml"),
        "version: 2\n\nsources:\n  - name: d0\n    tables:\n      - name: t_shared\n      - name: t0\n",
    )
    write(
        os.path.join(root, "dataset", "d1.yml"),
        "version: 2\n\nsources:\n  - name: d1\n    tables:\n      - name: t_shared\n",
    )

    nodes = {}
    for i in range(args.models):
        uid = "model.scale.m_%05d" % i
        dep = ["source.scale.d0.t_shared"] if i == 0 else ["model.scale.m_%05d" % (i - 1)]
        nodes[uid] = {
            "name": "m_%05d" % i,
            "resource_type": "model",
            "package_name": "scale",
            "original_file_path": "models/m_%05d.sql" % i,
            "depends_on": {"nodes": dep},
        }
    sources = {}
    for dataset, tables in (("d0", ("t_shared", "t0")), ("d1", ("t_shared",))):
        for table in tables:
            uid = "source.scale.%s.%s" % (dataset, table)
            sources[uid] = {
                "name": table,
                "resource_type": "source",
                "source_name": dataset,
                "package_name": "scale",
                "original_file_path": "dataset/%s.yml" % dataset,
            }
    write(
        os.path.join(root, "target", "manifest.json"),
        json.dumps({"metadata": {"project_name": "scale"}, "nodes": nodes, "sources": sources}),
    )
    print("wrote %d models to %s" % (args.models, root))


if __name__ == "__main__":
    main()
