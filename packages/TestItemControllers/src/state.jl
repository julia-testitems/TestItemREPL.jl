"""
    TestProcessState

Mutable state for a single test process managed by the reactor.
"""
mutable struct TestProcessState
    id::String
    fsm::FSM{TestProcessPhase}
    env::TestEnvironment
    testrun_id::Union{Nothing,String}
    jl_process::Union{Nothing,Base.Process}
    endpoint::Union{Nothing,JSONRPC.JSONRPCEndpoint}
    debug_pipe_name::String
    current_testitem_id::Union{Nothing,String}
    current_testitem_started_at::Union{Nothing,Float64}
    timeout_cs::Union{Nothing,CancellationTokens.CancellationTokenSource}
    timeout_reg::Any  # Union{Nothing,CancellationTokens.CancellationTokenRegistration}
    # Process lifecycle
    cs::CancellationTokens.CancellationTokenSource        # process-level cancellation
    julia_proc_cs::Union{Nothing,CancellationTokens.CancellationTokenSource}  # per-launch
    is_precompile_process::Bool
    precompile_done::Bool
    test_env_content_hash::Union{Nothing,String}
    # Per-testrun context (set when assigned to a testrun, cleared on return to pool)
    testrun_token::Union{Nothing,CancellationTokens.CancellationToken}
    testrun_watcher_registration::Any
    test_setups::Any     # Union{Nothing, Vector{TestsetupDetails}}
    coverage_root_uris::Any
    proc_log_level::Symbol
end

function TestProcessState(id::String, env::TestEnvironment;
        is_precompile_process::Bool=false,
        precompile_done::Bool=false,
        test_env_content_hash=nothing)
    return TestProcessState(
        id,
        testprocess_fsm(id),
        env,
        nothing,                                        # testrun_id
        nothing,                                        # jl_process
        nothing,                                        # endpoint
        JSONRPC.generate_pipe_name(),                   # debug_pipe_name
        nothing,                                        # current_testitem_id
        nothing,                                        # current_testitem_started_at
        nothing,                                        # timeout_cs
        nothing,                                        # timeout_reg
        CancellationTokens.CancellationTokenSource(),   # cs
        nothing,                                        # julia_proc_cs
        is_precompile_process,
        precompile_done,
        test_env_content_hash,
        nothing,                                        # testrun_token
        nothing,                                        # testrun_watcher_registration
        nothing,                                        # test_setups
        nothing,                                        # coverage_root_uris
        :Info,                                          # proc_log_level
    )
end

"""
    TestRunState

Mutable state for a single test run managed by the reactor.
"""
mutable struct TestRunState
    id::String
    fsm::FSM{TestRunPhase}
    profiles::Vector{TestProfile}
    remaining_items::Dict{String,TestItemDetail}   # id → item (not yet completed)
    test_setups::Vector{TestSetupDetail}
    procs::Union{Nothing,Dict{TestEnvironment,Vector{String}}}  # process IDs by env
    testitem_ids_by_proc::Dict{String,Vector{String}}
    stolen_ids_by_proc::Dict{String,Vector{String}}
    items_dispatched_to_procs::Set{String}
    processes_ready_before_acquired::Set{String}
    coverage::Vector{CoverageTools.FileCoverage}
    cancellation_source::CancellationTokens.CancellationTokenSource
    completion_channel::Channel{Any}    # reactor puts result here; execute_testrun waits on it
end

function TestRunState(
    id::String,
    profiles::Vector{TestProfile},
    items::Vector{TestItemDetail},
    test_setups::Vector{TestSetupDetail};
    token::Union{Nothing,CancellationTokens.CancellationToken}=nothing,
)
    cancellation_source = token === nothing ?
        CancellationTokens.CancellationTokenSource() :
        CancellationTokens.CancellationTokenSource(token)

    return TestRunState(
        id,
        testrun_fsm(id),
        profiles,
        Dict{String,TestItemDetail}(item.id => item for item in items),
        test_setups,
        nothing,                                    # procs
        Dict{String,Vector{String}}(),              # testitem_ids_by_proc
        Dict{String,Vector{String}}(),              # stolen_ids_by_proc
        Set{String}(),                              # items_dispatched_to_procs
        Set{String}(),                              # processes_ready_before_acquired
        CoverageTools.FileCoverage[],               # coverage
        cancellation_source,
        Channel{Any}(1),                            # completion_channel
    )
end
