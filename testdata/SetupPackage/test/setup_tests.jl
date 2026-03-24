@testmodule ConfigSetup begin
    using SetupPackage
    const CONFIG = get_config()
end

@testsnippet SharedSnippet begin
    shared_value = 42
end

@testitem "transform with module setup" setup=[ConfigSetup] begin
    using SetupPackage
    @test transform(3, ConfigSetup.CONFIG) == 35
end

@testitem "uses snippet setup" setup=[SharedSnippet] begin
    @test shared_value == 42
end
