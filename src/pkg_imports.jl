include("../packages/PrecompileTools/src/PrecompileTools.jl")
include("../packages/AutoHashEquals/src/AutoHashEquals.jl")
include("../packages/ExceptionUnwrapping/src/ExceptionUnwrapping.jl")
include("../packages/JuliaSyntax/src/JuliaSyntax.jl")
include("../packages/MacroTools/src/MacroTools.jl")
include("../packages/ProgressMeter/src/ProgressMeter.jl")
include("../packages/ReplMaker/src/ReplMaker.jl")
include("../packages/TestItemControllers/src/TestItemControllers.jl")

module TestItemDetection
    import ..JuliaSyntax
    using ..JuliaSyntax: @K_str, kind, children, SyntaxNode

    include("../packages/TestItemDetection/src/packagedef.jl")
end

module Salsa
    export @derived, @declare_input, Runtime, DerivedFunctionException

    import ..ExceptionUnwrapping
    import ..MacroTools
    include("../packages/Salsa/src/packagedef.jl")
end

module JuliaWorkspaces
    import UUIDs
    using UUIDs: UUID, uuid4
    
    using ..JuliaSyntax
    using ..JuliaSyntax: @K_str, kind, children, haschildren, first_byte, last_byte, SyntaxNode
    using ..AutoHashEquals
    using ..TestItemControllers.CancellationTokens
    using ..Salsa
    using ..TestItemDetection

    include("../packages/JuliaWorkspaces/src/packagedef.jl")
end
