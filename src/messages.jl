"""Messages processed by the reactor event loop."""
abstract type ReactorMessage end

# ═══════════════════════════════════════════════════════════════════════════════
# Controller-level messages (handled by the reactor)
# ═══════════════════════════════════════════════════════════════════════════════

struct ShutdownMsg <: ReactorMessage end

struct GetProcsForTestRunMsg <: ReactorMessage
    testrun_id::String
    proc_count_by_env::Dict{TestEnvironment,Int}
    env_content_hash_by_env::Dict{TestEnvironment,Union{Nothing,String}}
    test_setups::Vector{TestItemServerProtocol.TestsetupDetails}
    coverage_root_uris::Union{Nothing,Vector{String}}
    log_level::Symbol
end

struct ReturnToPoolMsg <: ReactorMessage
    testprocess_id::String
    env::TestEnvironment
end

struct TestProcessTerminatedMsg <: ReactorMessage
    testprocess_id::String
end

struct TestProcessStatusChangedMsg <: ReactorMessage
    testprocess_id::String
    status::String
end

struct TestProcessOutputMsg <: ReactorMessage
    testprocess_id::String
    output::String
end

# ═══════════════════════════════════════════════════════════════════════════════
# Test-run messages (handled by the reactor)
# ═══════════════════════════════════════════════════════════════════════════════

struct ProcsAcquiredMsg <: ReactorMessage
    testrun_id::String
    procs::Dict{TestEnvironment,Vector{String}}  # env → process IDs
end

struct TestRunCancelledMsg <: ReactorMessage
    testrun_id::String
end

struct ReadyToRunTestItemsMsg <: ReactorMessage
    testrun_id::String
    testprocess_id::String
end

struct PrecompileDoneMsg <: ReactorMessage
    testrun_id::String
    env::TestEnvironment
    testprocess_id::String
end

struct AttachDebuggerMsg <: ReactorMessage
    testrun_id::String
    debug_pipe_name::String
end

struct TestItemStartedMsg <: ReactorMessage
    testrun_id::String
    testprocess_id::String
    testitem_id::String
end

struct TestItemPassedMsg <: ReactorMessage
    testrun_id::String
    testprocess_id::String
    testitem_id::String
    duration::Float64
    coverage::Union{Missing,Vector{Any}}  # Missing or Vector{FileCoverage}
end

struct TestItemFailedMsg <: ReactorMessage
    testrun_id::String
    testprocess_id::String
    testitem_id::String
    messages::Vector{Any}
    duration::Union{Float64,Missing}
end

struct TestItemErroredMsg <: ReactorMessage
    testrun_id::String
    testprocess_id::String
    testitem_id::String
    messages::Vector{Any}
    duration::Union{Float64,Missing}
end

struct TestItemSkippedStolenMsg <: ReactorMessage
    testrun_id::String
    testprocess_id::String
    testitem_id::String
end

struct AppendOutputMsg <: ReactorMessage
    testrun_id::String
    testprocess_id::String
    testitem_id::Union{Nothing,String}
    output::String
end

struct TestProcessTerminatedInRunMsg <: ReactorMessage
    testrun_id::String
    testprocess_id::String
    skip_remaining::Bool
end

struct TestItemTimeoutMsg <: ReactorMessage
    testrun_id::String
    testprocess_id::String
    testitem_id::String
end

# ═══════════════════════════════════════════════════════════════════════════════
# Process-lifecycle messages (from IO tasks → reactor)
# ═══════════════════════════════════════════════════════════════════════════════

struct TestProcessLaunchedMsg <: ReactorMessage
    testprocess_id::String
    jl_process::Base.Process
    endpoint::JSONRPC.JSONRPCEndpoint
end

struct TestProcessActivatedMsg <: ReactorMessage
    testprocess_id::String
end

struct TestProcessTestSetupsLoadedMsg <: ReactorMessage
    testprocess_id::String
end

struct TestProcessReviseResultMsg <: ReactorMessage
    testprocess_id::String
    needs_restart::Bool
end

struct TestProcessIOErrorMsg <: ReactorMessage
    testprocess_id::String
    error_type::Symbol  # :restart or :fatal
end

struct ActivationFailedMsg <: ReactorMessage
    testprocess_id::String
    error_message::String
end

struct TerminateTestProcessMsg <: ReactorMessage
    testprocess_id::String
end


