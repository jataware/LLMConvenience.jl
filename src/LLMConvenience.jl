module LLMConvenience

export handle_response, fetch_docs, installed_dependencies, get_source, session_state, parse_check
import Pkg
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
    handle_response(docs)
end

"""
Fetch docs for module and its members
"""
function fetch_docs(mod::Module)
    docs = Dict(:module => get_doc(mod))
    docs[:functions] = Dict(func => get_doc(func) for func in names(mod))
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

struct VarInfo
    value::Any
    type::String
end

struct SessionState
    user_vars::Dict{Symbol, VarInfo}
    imported_modules::Dict{Symbol, Module}
    callables::Dict{Symbol, Any}
end

SessionState(d::AbstractDict) = SessionState(
    Dict(name => VarInfo(entry[:value], entry[:type]) for (name, entry) in d[:user_vars]),
    d[:imported_modules],
    d[:callables]
)

"""
Handle conversion to `application/json` content type for SessionState

A separate method is needed since `SessionState` cannot use StructTypes
"""
function handle_response(state::SessionState)
    dict = Dict(
        :user_vars => Dict(
            var => Dict(
                :value => var_info.value,
                :type => var_info.type
            ) for (var, var_info) in state.user_vars
        ),
        :imported_modules => keys(state.imported_modules),
        :callables => keys(state.callables)
    )
    handle_response(dict)
end

"""
Expression that indicates the currently available modules, user-defined variables, and callables 
like functions in the current session.

Currently, this pollutes the global namespace with 'hidden' variables i.e variables prepended with '_'.
"""
function session_state() 
    state = @eval Main begin
        _ignored_symbols = [:Base, :Core, :InteractiveUtils, :Main, :LLMConvenience]
        _is_hidden_name(s) = string(s)[1] ∈ ['_', '#'] || s ∈ _ignored_symbols
        _is_hidden(s) = _is_hidden_name(s)

        _state = Dict(
            :user_vars => Dict(),
            :imported_modules => Dict{Symbol, Module}(),
            :callables => Dict{Symbol, Any}(),
        )
        _var_names = filter(!_is_hidden, names(Main; all=true, imported=true))
        for var in _var_names
            value = getproperty(Main, var)
            if isa(value, Module)
                _state[:imported_modules][var] = value
            elseif typeof(value) <: Function
                _state[:callables][var] = value
            else
                _state[:user_vars][var] = Dict(
                    :value => string(value),
                    :type => string(typeof(value))
                )
            end
        end
        _state
    end
    SessionState(state)
end


struct Result 
    success::Bool
    reason::Union{String, Nothing}
end

StructTypes.StructType(::Type{Result}) = StructTypes.Struct()

"""
Check if the given code will parse
"""
function parse_check(code::AbstractString)
    expr = nothing
    try
        expr = Meta.parse(code)
    catch e
        Result(false, string(e))
    else
        success = expr.head !== :incomplete
        Result(success, string(expr))
    end
end

"""
Execute code in a sandboxed REPL environment
"""
function eval_sandboxed(expr::Expr)
    state = session_state()
    try
        eval(expr)
    catch e
        e
    end

end

function eval_sandboxed(code::AbstractString)
    parse_result = parse_check(code) 
    if !parse_result.success
        parse_result
    else 
        eval_sandboxed(Meta.parse(code))
    end
end


end # module LLMConvenience
