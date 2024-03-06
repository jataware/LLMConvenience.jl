module LLMConvenience

export handle_response, get_member_docs, session_state
import Pkg
using Revise
import CodeTracking: definition, signature_at, whereis
import Malt
import JSON3, DisplayAs


handle_response(dict::AbstractDict) = DisplayAs.unlimited(JSON3.write(dict))
handle_response(x) = handle_response(Dict("result" => x))


"""
Provide docs for members in `Main` given a string containing comma-separated function names.
"""
function get_member_docs(raw_string::String)
    member_names = split(raw_string, ",")
    get_member_docs(member_names)
end

function get_doc(x::Symbol, module_name::Symbol)
    doc = eval(:(@doc $module_name.$x))
    if length(doc) >= 23 && doc[1:23] == "No documentation found."
        nothing
    else
        string(doc)
    end
end

"""
Provide docs for selected members currently available in `Main`
"""
function get_member_docs(member_names::AbstractVector{<:AbstractString}; mod::Module=Main)
    docs = Dict(func => get_doc(func, Symbol(mod)) for func in Symbol.(member_names))
    handle_response(docs)
end

function installed_dependencies()
    keys(Pkg.project().dependencies)
end

get_source(method::Method) = method |> string ∘ definition

function get_source(func)
    methods_source = Dict{String, String}()
    for method in methods(func)
        pretty_name = split(string(method), " @")[1]
        methods_source[pretty_name] = get_source(method)
    end
    methods_source
end

function get_source(mod::Module)
    source = Dict{String, Dict{String, String}}()
    lineage(field) = split(string(field), ".")
    for field in names(mod; all=true, imported=true)
        if lineage(mod)[end] ∉ lineage(field) && '#' ∉ string(field)
            func = getfield(mod, field)
            field_source = get_source(func)
            if !isempty(field_source)
                source[string(field)] = field_source
            end
        end
    end
    source
end

# """
# Show docs for module under the `:module` key and individual function Documentation
# is under the `:functions` key.
# """
# function get_mod_docs(mod::Module)
#     docs = Dict(:module => get_doc(mod))
#     docs[:functions] = Dict(func => get_doc(func) for func in names(mod))
#     handle_response(docs)
# end

# get_mod_docs(mod::AbstractString) = mod |> get_mod_docs ∘ Symbol

# function get_mod_docs(mod::Symbol)
#     docs = Dict(:module => get_doc(mod))
#     docs[:functions] = Dict(func => get_doc(func) for func in names(mod))
#     handle_response(docs)
# end

"""
Expression that indicates the currently available modules and user-defined variables in the current session.
"""
session_state = 
    # TODO: Run this within the module instead of exporting an expression
    quote
        _ignored_symbols = [:Base, :Core, :InteractiveUtils, :Main, :LLMConvenience]
        _is_visible_type(s) = any((x) -> isa(eval(:(Main.$(s))), x), [DataType, Function, Module]) 
        _is_hidden_name(s) = string(s)[1] == '_' || s ∈ _ignored_symbols
        _is_hidden(s) = _is_hidden_name(s) || !_is_visible_type(s)

        _state = Dict(
            :user_vars => Dict(),
            :imported_modules => [],
        )
        _var_names = filter(!_is_hidden, names(Main))
        for var in _var_names
            value = getproperty(Main, var)
            if isa(value, Module)
                push!(_state[:imported_modules], var)
            else
                _state[:user_vars][var] = string(value)
            end
        end
        _state
    end


end # module LLMConvenience
