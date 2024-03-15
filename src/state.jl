struct VarInfo
    value::Any
    type::String
end

struct SessionState
    user_vars::Dict{Symbol, VarInfo}
    imported_modules::Vector{Symbol}
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
        :imported_modules => state.imported_modules,
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
        _is_hidden_name(s) = string(s)[1] ∈ ['_', '#'] || s ∈ _ignored_symbols || s ∈ names(Base.MainInclude; all=true)
        _is_hidden(s) = _is_hidden_name(s)

        _state = Dict(
            :user_vars => Dict(),
            :imported_modules => Vector{Symbol}(),
            :callables => Dict{Symbol, Any}(),
        )
        _var_names = filter(!_is_hidden, names(Main; all=true, imported=true))
        for var in _var_names
            value = getproperty(Main, var)
            if isa(value, Module)
                push!(_state[:imported_modules], var)
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