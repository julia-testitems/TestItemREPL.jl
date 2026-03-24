mutable struct JSONRPCTestItemController{ERR_HANDLER<:Function}
    err_handler::Union{Nothing,ERR_HANDLER}
    endpoint::JSONRPC.JSONRPCEndpoint
    controller::TestItemController

    function JSONRPCTestItemController(
        pipe_in,
        pipe_out,
        err_handler::ERR_HANDLER;
        error_handler_file=nothing,
        crash_reporting_pipename=nothing) where {ERR_HANDLER<:Union{Function,Nothing}}

        endpoint = JSONRPC.JSONRPCEndpoint(pipe_in, pipe_out)

        jr = new{ERR_HANDLER}(err_handler, endpoint)

        # Helper: send a JSONRPC notification, swallowing transport/endpoint errors.
        # These callbacks run on the reactor thread; if the endpoint has closed
        # (e.g. client disconnected), we must not let the exception propagate
        # because it would interrupt the reactor's handle!() mid-execution and
        # could prevent _check_testrun_complete!() from being reached.
        function _safe_send(args...)
            try
                JSONRPC.send(jr.endpoint, args...)
            catch err
                if err isa JSONRPC.TransportError || err isa JSONRPC.JSONRPCError
                    @debug "JSONRPC callback send failed (endpoint closed?)" exception=(err,)
                else
                    rethrow()
                end
            end
        end

        callbacks = ControllerCallbacks(
            on_testitem_started = (testrun_id, testitem_id) -> _safe_send(
                TestItemControllerProtocol.notficiationTypeTestItemStarted,
                TestItemControllerProtocol.TestItemStartedParams(
                    testRunId=testrun_id,
                    testItemId=testitem_id
                )
            ),
            on_testitem_passed = (testrun_id, testitem_id, duration) -> _safe_send(
                TestItemControllerProtocol.notficiationTypeTestItemPassed,
                TestItemControllerProtocol.TestItemPassedParams(
                    testRunId=testrun_id,
                    testItemId=testitem_id,
                    duration=duration
                )
            ),
            on_testitem_failed = (testrun_id, testitem_id, messages, duration) -> _safe_send(
                TestItemControllerProtocol.notficiationTypeTestItemFailed,
                TestItemControllerProtocol.TestItemFailedParams(
                    testRunId=testrun_id,
                    testItemId=testitem_id,
                    messages=messages,
                    duration=duration
                )
            ),
            on_testitem_errored = (testrun_id, testitem_id, messages, duration) -> _safe_send(
                TestItemControllerProtocol.notficiationTypeTestItemErrored,
                TestItemControllerProtocol.TestItemErroredParams(
                    testRunId=testrun_id,
                    testItemId=testitem_id,
                    messages=messages,
                    duration=duration
                )
            ),
            on_testitem_skipped = (testrun_id, testitem_id) -> _safe_send(
                TestItemControllerProtocol.notficiationTypeTestItemSkipped,
                (testRunId=testrun_id, testItemId=testitem_id)
            ),
            on_append_output = (testrun_id, testitem_id, output) -> _safe_send(
                TestItemControllerProtocol.notficiationTypeAppendOutput,
                TestItemControllerProtocol.AppendOutputParams(
                    testRunId=testrun_id,
                    testItemId=something(testitem_id, missing),
                    output=output
                )
            ),
            on_attach_debugger = (testrun_id, debug_pipename) -> _safe_send(
                TestItemControllerProtocol.notificationTypeLaunchDebugger,
                (;
                    debugPipeName = debug_pipename,
                    testRunId = testrun_id
                )
            ),
            on_process_created = (id, package_name, package_uri, project_uri, coverage, env) -> _safe_send(
                TestItemControllerProtocol.notificationTypeTestProcessCreated,
                TestItemControllerProtocol.TestProcessCreatedParams(
                    id = id,
                    packageName = package_name,
                    packageUri = something(package_uri, missing),
                    projectUri = something(project_uri, missing),
                    coverage = coverage,
                    env = env
                )
            ),
            on_process_terminated = id -> _safe_send(
                TestItemControllerProtocol.notificationTypeTestProcessTerminated,
                (;id = id)
            ),
            on_process_status_changed = (id, status) -> _safe_send(
                TestItemControllerProtocol.notificationTypeTestProcessStatusChanged,
                TestItemControllerProtocol.TestProcessStatusChangedParams(id = id, status = status)
            ),
            on_process_output = (id, output) -> _safe_send(
                TestItemControllerProtocol.notificationTypeTestProcessOutput,
                TestItemControllerProtocol.TestProcessOutputParams(id = id, output = output)
            ),
        )

        jr.controller = TestItemController(callbacks, err_handler; error_handler_file=error_handler_file, crash_reporting_pipename=crash_reporting_pipename)

        return jr
    end
end

function create_testrun_request(params::TestItemControllerProtocol.CreateTestRunParams, jr_controller::JSONRPCTestItemController, token)
    @debug "Received create_testrun request" testrun_id=params.testRunId profile_count=length(params.testProfiles) testitem_count=length(params.testItems) testsetup_count=length(params.testSetups)
    ret =  execute_testrun(
        jr_controller.controller,
        params.testRunId,
        [
            TestProfile(
                i.id,
                i.label,
                i.juliaCmd,
                i.juliaArgs,
                i.juliaNumThreads,
                i.juliaEnv,
                i.maxProcessCount,
                i.mode,
                coalesce(i.coverageRootUris,nothing),
                jr_controller.controller.log_level
            ) for i in params.testProfiles
        ],
        [
            TestItemDetail(
                i.id,
                i.uri,
                i.label,
                coalesce(i.packageName, nothing),
                coalesce(i.packageUri, nothing),
                coalesce(i.projectUri, nothing),
                coalesce(i.envContentHash, nothing),
                i.useDefaultUsings,
                i.testSetups,
                i.line,
                i.column,
                i.code,
                i.codeLine,
                i.codeColumn,
                coalesce(i.timeout, nothing)
            )
            for i in params.testItems
        ],
        [
            TestSetupDetail(
                i.packageUri,
                i.name,
                i.kind,
                i.uri,
                i.line,
                i.column,
                i.code
            ) for i in params.testSetups
        ],
        token
    )

    @debug "Finished create_testrun request" testrun_id=params.testRunId coverage_files=ismissing(ret) ? missing : length(ret)
    return TestItemControllerProtocol.CreateTestRunResponse("success", ret)
end

function terminate_test_process_request(params::TestItemControllerProtocol.TerminateTestProcessParams, json_controller::JSONRPCTestItemController, token)
    @debug "Received terminate_test_process request" id=params.testProcessId
    terminate_test_process(json_controller.controller, params.testProcessId)
end

JSONRPC.@message_dispatcher dispatch_msg begin
    TestItemControllerProtocol.create_testrun_request_type => create_testrun_request
    TestItemControllerProtocol.terminate_test_process_request_type => terminate_test_process_request
end

function Base.run(jr_controller::JSONRPCTestItemController)
    @debug "Starting JSON-RPC controller endpoint"
    JSONRPC.start(jr_controller.endpoint)

    @async try
        while true
            msg = JSONRPC.get_next_message(jr_controller.endpoint)
            @debug "Received JSON-RPC message" method=msg.method

            @async try
                @debug "Dispatching JSON-RPC message asynchronously" method=msg.method
                dispatch_msg(jr_controller.endpoint, msg, jr_controller)
            catch err
                bt = catch_backtrace()
                if jr_controller.err_handler !== nothing
                    jr_controller.err_handler(err, bt)
                else
                    @error "Error dispatching message" exception=(err, bt)
                end
            end
        end
    catch err
        if err isa JSONRPC.TransportError || err isa JSONRPC.JSONRPCError
            @debug "JSONRPC message loop ended" reason=err.msg
        else
            bt = catch_backtrace()
            if jr_controller.err_handler !== nothing
                jr_controller.err_handler(err, bt)
            else
                @error "Error in JSONRPC message loop" exception=(err, bt)
            end
        end
    end

    run(jr_controller.controller)
end
