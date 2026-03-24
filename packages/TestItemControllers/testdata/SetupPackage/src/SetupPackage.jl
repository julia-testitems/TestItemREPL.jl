module SetupPackage

export get_config, transform

get_config() = Dict("multiplier" => 10, "offset" => 5)

transform(x, config) = x * config["multiplier"] + config["offset"]

end # module SetupPackage
