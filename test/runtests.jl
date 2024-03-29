import LLMConvenience:  handle_response, 
                        fetch_docs, 
                        installed_dependencies, 
                        fetch_source, 
                        session_state, 
                        parse_check, 
                        use_sandbox
import JSON3
import Test: @test, @testset
import InteractiveUtils: @which

@testset "Response Handling" begin
    @test handle_response("Some Result").content == "{\"result\":\"Some Result\"}"
end

"""
ExampleModule docs
"""
module ExampleModule
    export example_function, ExampleStruct
    "example_function docs"
    function example_function()
        "This is an example function"
    end

    "ExampleStruct docs"
    struct ExampleStruct
        x::Int
    end
end
using .ExampleModule

@testset "Member Documentation" begin
    @test fetch_docs("example_function")[:example_function] == "example_function docs\n"
    @test occursin("No docstring found for module `JSON3`", fetch_docs(JSON3)[:module])
end

@testset "Installed Dependencies" begin
    @test "Pkg" in installed_dependencies()
end

@testset "Source" begin
    source = fetch_source(JSON3)
    @test "readjsonlines" ∈ keys(source)
end

global test_var = "some value"
@testset "State Capture" begin
    state = session_state()
    state_as_json = JSON3.read(handle_response(state).content)
    user_vars = state.user_vars
    imported_modules = state.imported_modules
    callables = keys(state.callables)
    #@test test_var ∈ keys(user_vars) && user_vars[test_var][:value] == "some value"   
    @test :session_state ∈ callables
    @test :ExampleModule ∈ imported_modules
    @test :DisplayAs ∉ imported_modules
    @test length(state_as_json[:user_vars]) == length(user_vars)
end

@testset "Parseable" begin
    @test parse_check("1 + 1").success
    @test !parse_check("1 +").success
end

@testset "Sandbox" begin
    function add_1_1(_, sandbox) 
        sandbox(:(1 + 1))
    end
    @test use_sandbox(add_1_1) == 2
end