import LLMConvenience: handle_response, get_member_docs, installed_dependencies, get_source, session_state
import JSON3
import Test: @test, @testset


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
    @test get_member_docs("example_function").content == "{\"example_function\":\"example_function docs\\n\"}"
    #@test JSON3.read(get_member_docs(ExampleModule).content).ExampleStruct == "ExampleStruct docs\n"
end

@testset "Installed Dependencies" begin
    @test "Pkg" in installed_dependencies()
end

@testset "Source" begin
    source = get_source(JSON3)
    @test "readjsonlines" ∈ keys(source)
end

@testset "State Capture" begin
    test_var = "some value"
    state = eval(session_state)
    user_vars = state[:user_vars]
    imported_modules = state[:imported_modules]
    @test test_var ∈ keys(user_vars) && user_vars[test_var] == "some value"   
    @test :ExampleModule ∈ imported_modules
    @test :DisplayAs ∉ imported_modules
end


