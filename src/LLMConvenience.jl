module LLMConvenience

export handle_response, fetch_docs, installed_dependencies, fetch_source, session_state, parse_check, use_sandbox, mod_docs, mod_source
import Pkg
import Serialization: serialize, deserialize
using Revise
import CodeTracking: definition, signature_at, whereis
import StructTypes, JSON3, DisplayAs
import Malt


"""
Return response as an `application/json` content type
"""
function handle_response end
handle_response(obj) = DisplayAs.unlimited(JSON3.write(obj))
handle_response(x::AbstractString) = handle_response(Dict("result" => x))


function get_doc(x)
    doc = eval(:(@doc $x))
    if length(doc) >= 23 && doc[1:23] == "No documentation found."
        nothing
    else
        string(doc)
    end
end

function get_doc(x::Symbol, module_name::Symbol=:Main)
    get_doc(:($module_name.$x))
end


"""
Provide docs for members in `Main` given a string containing comma-separated function names.
"""
function fetch_docs(raw_string::String)
    member_names = Symbol.(split(raw_string, ","))
    fetch_docs(member_names, :Main)
end

"""
Provide docs for selected members
"""
function fetch_docs(member_names::AbstractVector{Symbol}, module_name::Symbol = :Main)
    docs = Dict(func => get_doc(func, module_name) for func in member_names)
    docs
end

"""
Fetch docs for modules
"""
function fetch_docs(mod::Module)
    mod_name = Symbol(mod)
    docs = Dict{Symbol, Any}(:module => string(eval(:(@doc $mod_name))))
    docs[:members] = Dict(func => get_doc(func, Symbol(mod)) for func in names(mod;all=true))
    docs
end


fetch_source(method::Method) = method |> string ∘ definition

function fetch_source(func)
    methods_source = Dict{String, String}()
    for method in methods(func)
        pretty_name = split(string(method), " @")[1]
        methods_source[pretty_name] = fetch_source(method)
    end
    methods_source
end

function fetch_source(mod::Module)
    source = Dict{String, Dict{String, String}}()
    lineage(field) = split(string(field), ".")
    for field in names(mod; all=true, imported=true)
        if lineage(mod)[end] ∉ lineage(field) && '#' ∉ string(field)
            func = getfield(mod, field)
            field_source = fetch_source(func)
            if !isempty(field_source)
                source[string(field)] = field_source
            end
        end
    end
    source
end

function installed_dependencies()
    keys(Pkg.project().dependencies)
end

include("state.jl")
include("branching.jl")

function mod_operation(name::Symbol, op::Symbol)
    use_sandbox() do _, sandbox
        quote
            using LLMConvenience
            import $name
            $op($name)
        end |> result(sandbox)
    end
end

mod_docs(name::Symbol) = mod_operation(name, :fetch_docs)
mod_source(name::Symbol) = mod_operation(name, :fetch_source)

end # module LLMConvenience
