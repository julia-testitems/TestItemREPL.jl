@info "Julia test item process precompiling"

# Activate the version-specific environment. We use Base.ACTIVE_PROJECT[]
# (available since Julia 1.0) instead of Pkg.activate, because Pkg may not
# be available in the default environment on Julia 1.12+ (no implicit Pkg
# in empty projects). Fall back to Pkg.activate for safety.
version_specific_env_path = joinpath(@__DIR__, "../environments", "v$(VERSION.major).$(VERSION.minor)")
let env_path = isdir(version_specific_env_path) ? version_specific_env_path : joinpath(@__DIR__, "../environments", "fallback")
    if isdefined(Base, :ACTIVE_PROJECT)
        Base.ACTIVE_PROJECT[] = env_path
    else
        import Pkg
        Pkg.activate(env_path)
    end
end

let
    has_error_handler = false

    try

        if length(ARGS) > 0
            include(ARGS[1])
            has_error_handler = true
        end

        using TestItemServer
    catch err
        bt = catch_backtrace()
        if has_error_handler
            Base.invokelatest(global_err_handler, err, bt, Base.ARGS[2], "Test Process")
        else
            rethrow(err)
        end
    end
end
