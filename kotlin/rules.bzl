# ################################################################
# Execution phase
# ################################################################

def _kotlin_compile_impl(ctx):
    kt_jar = ctx.outputs.kt_jar
    inputs = []
    args = []

    # Single output jar
    args += ["-d", kt_jar.path]

    # Advanced options
    args += ["-X%s" % opt for opt in ctx.attr.x_opts]

    # Plugin options
    for k, v in ctx.attr.plugin_opts.items():
        args += ["-P"]
        args += ["plugin:%s=\"%s\"" % (k, v)]

    # Make classpath if needed.  Include those from this and dependent rules.
    jars = []

    # Populate from (transitive) java dependencies
    for dep in ctx.attr.java_deps:
        # Add-in all source and generated jar files
        for file in dep.files:
            jars.append(file)
        # Add-in transitive dependencies
        for file in dep.java.transitive_deps:
            jars.append(file)

    # Populate from (transitive) kotlin dependencies
    for dep in ctx.attr.deps:
        if hasattr(dep, "kt"):
            jars += [file for file in dep.kt.transitive_jars]
        if hasattr(dep, "android") and dep.android.defines_resources:
            jars += [dep.android.resource_jar.class_jar]

    # Populate from jar dependencies
    for fileset in ctx.attr.jars:
        # The fileset object is either a ConfiguredTarget OR a depset.
        files = getattr(fileset, 'files', None)
        if files:
            for file in files:
                jars += [file]
        else:
            for file in fileset:
                jars += [file]

    if jars:
        # De-duplicate
        jarsetlist = list(set(jars))
        args += ["-cp", ":".join([file.path for file in jarsetlist])]
        inputs += jarsetlist

    # Need to traverse back up to execroot, then down again
    kotlin_home = ctx.executable._kotlinc.dirname \
                  + "/../../../../../external/com_github_jetbrains_kotlin"

    # Add in filepaths
    for file in ctx.files.srcs:
        inputs += [file]
        args += [file.path]

    # Run the compiler
    ctx.action(
        mnemonic = "KotlinCompile",
        inputs = inputs,
        outputs = [kt_jar],
        executable = ctx.executable._kotlinc,
        arguments = args,
        env = {
            "KOTLIN_HOME": kotlin_home,
        }
    )

    return struct(
        files = set([kt_jar]),
        runfiles = ctx.runfiles(collect_data = True),
        kt = struct(
            srcs = ctx.attr.srcs,
            jar = kt_jar,
            transitive_jars = [kt_jar] + jars,
            home = kotlin_home,
        ),
    )


# ################################################################
# Analysis phase
# ################################################################

kt_filetype = FileType([".kt"])
jar_filetype = FileType([".jar"])
srcjar_filetype = FileType([".jar", ".srcjar"])

_kotlin_compile_attrs = {
    # kotlin sources
    "srcs": attr.label_list(
        allow_files = kt_filetype,
    ),

    # Dependent kotlin or android rules.
    "deps": attr.label_list(),

    # Dependent java rules.
    "java_deps": attr.label_list(
        providers = ["java"],
    ),

    # Not really implemented yet.
    "data": attr.label_list(
        allow_files = True,
        cfg = 'data',
    ),

    # Additional jar files to put on the kotlinc classpath
    "jars": attr.label_list(
        allow_files = jar_filetype,
    ),

    # Advanced options
    "x_opts": attr.string_list(),

    # Plugin options
    "plugin_opts": attr.string_dict(),

    # kotlin compiler (a shell script)
    "_kotlinc": attr.label(
        default=Label("@com_github_jetbrains_kotlin//:kotlinc"),
        executable = True,
        cfg = 'host',
    ),

    # kotlin runtime
    "_runtime": attr.label(
        default=Label("@com_github_jetbrains_kotlin//:runtime"),
    ),

}


_kotlin_compile_outputs = {
    "kt_jar": "%{name}.jar",
}


kotlin_compile = rule(
    implementation = _kotlin_compile_impl,
    attrs = _kotlin_compile_attrs,
    outputs = _kotlin_compile_outputs,
)


def kotlin_library(name, jars = [], java_deps = [], **kwargs):

    kotlin_compile(
        name = name,
        jars = jars,
        java_deps = java_deps,
        **kwargs
    )

    native.java_import(
        name = name + "_kt",
        jars = [name + ".jar"],
        deps = java_deps,
        exports = [
            "@com_github_jetbrains_kotlin//:runtime",
        ],
    )


def kotlin_binary(name,
                  jars = [],
                  srcs = [],
                  deps = [],
                  x_opts = [],
                  plugin_opts = {},
                  java_deps = [],
                  **kwargs):

    kotlin_compile(
        name = name + "_kt",
        jars = jars,
        java_deps = java_deps,
        srcs = srcs,
        deps = deps,
        x_opts = x_opts,
        plugin_opts = plugin_opts,
    )

    native.java_binary(
        name = name,
        runtime_deps = [
            name + "_kt.jar",
            "@com_github_jetbrains_kotlin//:runtime",
        ] + java_deps,
        **kwargs
    )


# ################################################################
# Loading phase
# ################################################################


KOTLIN_BUILD = """
package(default_visibility = ["//visibility:public"])
java_import(
    name = "runtime",
    jars = ["lib/kotlin-runtime.jar"],
)
sh_binary(
    name = "kotlin",
    srcs = ["bin/kotlin"],
)
sh_binary(
    name = "kotlinc",
    srcs = ["bin/kotlinc"],
)
"""

def kotlin_repositories():
    native.new_http_archive(
        name = "com_github_jetbrains_kotlin",
        url = "https://github.com/JetBrains/kotlin/releases/download/v1.1.2-2/kotlin-compiler-1.1.2-2.zip",
        sha256 = "57e18528f665675206e88cdc0bd42d1550b10f2508e08035270974d7abec3f2f",
        build_file_content = KOTLIN_BUILD,
        strip_prefix = "kotlinc",
    )
