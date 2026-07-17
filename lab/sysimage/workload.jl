# Precompile-execution workload for the sysimage: walk the exact user journey
# (load → plot → save) so its native code is baked into the image.
using Plots
p = plot(1:3, (1:3) .^ 2)
savefig(p, joinpath(mktempdir(), "warmup.png"))
