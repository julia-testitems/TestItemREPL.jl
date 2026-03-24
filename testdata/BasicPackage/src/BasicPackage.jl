module BasicPackage

export greet, add, buggy_func

greet() = "Hello from BasicPackage!"

add(a, b) = a + b

function buggy_func()
    error("this function is broken")
end

end # module BasicPackage
