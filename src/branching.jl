struct Result 
    success::Bool
    reason::Union{String, Nothing}
    output::Union{String, Nothing}
    function Result(success::Bool, reason::Union{Nothing, String} = nothing, output::Union{Nothing, String} = nothing)
        new(success, reason, output)
    end
end

StructTypes.StructType(::Type{Result}) = StructTypes.Struct()

function result(func)
    function wrapped(args...;kwargs...)
        output = nothing
        try
            output = func(args...;kwargs...)
        catch e
            Result(false, string(e))
        else
            Result(true, nothing, string(output))
        end
    end
end

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
        Result(success, nothing, string(expr))
    end
end

function use_sandbox(func::Function)
    mktempdir() do path
        worker = Malt.Worker()
        eval_in_worker(expr) = Malt.remote_eval_fetch(worker, expr)
        project_dir = dirname(Pkg.project().path)
        sandbox_dir = joinpath(path, basename(project_dir))
        cp(project_dir, sandbox_dir)
        eval_in_worker( 
            quote
                import Pkg
                Pkg.activate($sandbox_dir)
            end
        )
        result = func(path, eval_in_worker)
        Malt.stop(worker)
        result
    end
end


"""
Execute code in a sandboxed REPL environment
"""
function branched_eval(expr::Expr)
    state = session_state()
    project_dir = Pkg.project().path
    mktemp() do path, _
        serialize(path, state)
        worker = Malt.Worker()
        eval_in_worker(expr) = Malt.remote_eval_fetch(worker, expr) 
        eval_in_worker( 
            quote
                using Pkg
                Pkg.activate($project_dir)
                using LLMConvenience
                _state = deserialize($path)
            end
        )
        for name in state.imported_modules
            eval_in_worker(:(import $name))
        end
        for (name, _) in state.callables
            eval_in_worker(:($name = _state.callables[$(QuoteNode(name))]))
        end
        for (name, _) in state.user_vars
            eval_in_worker(:($name = _state.user_vars[$(QuoteNode(name))].value))
        end
        output = nothing
        output = eval_in_worker(expr)
        result = try
            output = eval_in_worker(expr)
        catch e
            Result(false, string(e))
        else
            Result(true, nothing, string(output))
        end
        Malt.stop(worker)
        result 
    end

end

function branched_eval(code::AbstractString)
    parse_result = parse_check(code) 
    if !parse_result.success
        parse_result
    else 
        branched_eval(Meta.parse(code))
    end
end