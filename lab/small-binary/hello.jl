# Minimal trim-safe entrypoint for juliac (WIP-limitation demo):
# the binary should contain only the code this path actually needs.
function (@main)(args::Vector{String})::Cint
    println(Core.stdout, "Hello, Lean Julia!")
    return 0
end
