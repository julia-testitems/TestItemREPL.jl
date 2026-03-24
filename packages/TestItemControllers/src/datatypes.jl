function makechunks(X::AbstractVector, n::Integer)
    if n<1
        error("n is smaller than 1")
    end
    c = length(X) ÷ n
    return [X[1+c*k:(k == n-1 ? end : c*k+c)] for k = 0:n-1]
end

struct TestProfile
    id::String
    label::String
    julia_cmd::String
    julia_args::Vector{String}
    julia_num_threads::Union{Missing,String}
    julia_env::Dict{String,Union{String,Nothing}}
    max_process_count::Int
    mode::String
    coverage_root_uris::Union{Nothing,Vector{String}}
    log_level::Symbol
end

struct TestItemDetail
    id::String
    uri::String
    label::String
    package_name::Union{Nothing,String}
    package_uri::Union{Nothing,String}
    project_uri::Union{Nothing,String}
    env_content_hash::Union{Nothing,String}
    option_default_imports::Bool
    test_setups::Vector{String}
    line::Int
    column::Int
    code::String
    code_line::Int
    code_column::Int
    timeout::Union{Nothing,Float64}
end

struct TestSetupDetail
    package_uri::String
    name::String
    kind::String
    uri::String
    line::Int
    column::Int
    code::String
end
