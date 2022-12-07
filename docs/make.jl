using WASMCompiler
using Documenter

DocMeta.setdocmeta!(WASMCompiler, :DocTestSetup, :(using WASMCompiler); recursive=true)

makedocs(;
    modules=[WASMCompiler],
    authors="arhik <arhik23@gmail.com>",
    repo="https://github.com/arhik/WASMCompiler.jl/blob/{commit}{path}#{line}",
    sitename="WASMCompiler.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://arhik.github.io/WASMCompiler.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/arhik/WASMCompiler.jl",
    devbranch="main",
)
