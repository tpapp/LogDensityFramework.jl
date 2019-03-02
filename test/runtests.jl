using LogDensityProblems
using LogDensityProblems: Value, ValueGradient
using Test

using Distributions
import ForwardDiff, Flux, ReverseDiff
using Parameters: @unpack
using DocStringExtensions: SIGNATURES
using TransformVariables
using Random: seed!

seed!(1)

"""
    a ≅ b

Compare fields and types (strictly), for unit testing.
"""
≅(::Any, ::Any) = false
≅(a::Value{T}, b::Value{T}) where {T} = a.value == b.value
≅(a::ValueGradient{T,V}, b::ValueGradient{T,V}) where {T,V} =
    a.value == b.value && (a.value == -Inf || a.gradient == b.gradient)

@testset "Value constructor" begin
    @test eltype(Value(1.0)) ≡ Float64
    @test_throws InvalidLogDensityException(0, Inf) Value(Inf)
    @test_throws InvalidLogDensityException Value(NaN) # FIXME more specific test
    @test isfinite(Value(1.0))
    @test !isinf(Value(1.0))
    @test !isfinite(Value(-Inf))
    @test isinf(Value(-Inf))
    @test_throws MethodError Value(:something)
end

@testset "ValueGradient constructor" begin
    @test eltype(ValueGradient(1.0, [2.0])) ≡ Float64
    @test_throws InvalidLogDensityException(0, Inf) ValueGradient(Inf, [1.0])
    @test_throws InvalidLogDensityException(1, Inf) ValueGradient(2.0, [Inf])
    @test !isfinite(ValueGradient(-Inf, [12.0]))
    @test isinf(ValueGradient(-Inf, [12.0]))
    @test isfinite(ValueGradient(1.0, [12.0]))
    @test !isinf(ValueGradient(1.0, [12.0]))
    @test ValueGradient(1, [2.0]) ≅ ValueGradient(1.0, [2.0]) # conversion
end

@testset "error printing" begin
    @test sprint(showerror, InvalidLogDensityException(0, NaN)) ==
        "InvalidLogDensityException: value is NaN"
    @test sprint(showerror, InvalidLogDensityException(1, Inf)) ==
        "InvalidLogDensityException: gradient[1] is Inf"
end


@testset "transformed Bayesian problem" begin
    t = as((y = asℝ₊, ))
    d = LogNormal(1.0, 2.0)
    logposterior = ((x, ), ) -> logpdf(d, x)

    # a Bayesian problem
    p = TransformedLogDensity(t, logposterior)
    @test dimension(p) == 1
    @test p.transformation ≡ t

    # gradient of a problem
    ∇p = ADgradient(:ForwardDiff, p)
    @test dimension(∇p) == 1
    @test parent(∇p).transformation ≡ t

    for _ in 1:100
        x = random_arg(p)
        θ, lj = transform_and_logjac(t, x)
        px = logdensity(Value, p, x)
        @test logpdf(d, θ.y) + lj ≈ (px::Value).value
        @test (logdensity(Value, ∇p, x)::Value).value ≈ px.value
        ∇px = logdensity(ValueGradient, ∇p, x)
        @test (∇px::ValueGradient).value ≈ px.value
        @test ∇px.gradient ≈ [ForwardDiff.derivative(x -> logpdf(d, exp(x)) + x, x[1])]
    end
end

@testset "chunk heuristics for ForwardDiff" begin
    @test LogDensityProblems.heuristic_chunks(82) == vcat(1:4:81, [82])
end

@testset "-∞ log densities" begin
    t = as(Array, 2)
    validx = x -> all(x .> 0)
    p = TransformedLogDensity(t, x -> validx(x) ?  sum(abs2, x)/2 : -Inf)
    ∇p = ADgradient(:ForwardDiff, p)

    @test dimension(p) == dimension(∇p) == dimension(t)
    @test p.transformation ≡ parent(∇p).transformation ≡ t

    for _ in 1:100
        x = random_arg(p)
        px = logdensity(Value, ∇p, x)
        ∇px = logdensity(ValueGradient, ∇p, x)
        @test px isa Value
        @test ∇px isa ValueGradient
        @test px.value ≈ ∇px.value
        if validx(x)
            @test isfinite(px)
            @test isfinite(∇px)
            @test ∇px.value ≈ sum(abs2, x)/2
            @test ∇px.gradient ≈ x
        else
            @test isinf(px)
            @test isinf(∇px)
        end
    end
end

@testset "benchmark ForwardDiff problems" begin
    ℓ = TransformedLogDensity(as(Array, 20), x -> -sum(abs2, x))
    b = LogDensityProblems.benchmark_ForwardDiff_chunks(ℓ)
    @test b isa Vector{Pair{Int,Float64}}
    @test length(b) ≤ 20
end

@testset "stresstest" begin
    f = x -> all(x .< 0) ? NaN : -sum(abs2, x)
    ℓ = TransformedLogDensity(as(Array, 2), f)
    failures = LogDensityProblems.stresstest(ℓ; N = 1000)
    @test 230 ≤ length(failures) ≤ 270
    @test all(x -> all(x .< 0), failures)
end

@testset "show" begin
    t = as(Array, 5)
    p = TransformedLogDensity(t, x -> -sum(abs2, x))
    @test repr(p) == "TransformedLogDensity of dimension 5"
    @test repr(ADgradient(:ForwardDiff, p; chunk = 2)) ==
        ("ForwardDiff AD wrapper for " * repr(p) * ", w/ chunk size 2")
    @test repr(ADgradient(:ReverseDiff, p)) == ("ReverseDiff AD wrapper for " * repr(p))
    @test repr(ADgradient(:ReverseDiff, p; tape = true)) ==
        ("ReverseDiff AD wrapper (compiled tape) for " * repr(p))
    @test repr(ADgradient(:Flux, p)) == ("Flux AD wrapper for " * repr(p))
end

@testset "AD via Flux" begin
    f(x) = -3*abs2(x[1])
    ℓ = TransformedLogDensity(as(Array, asℝ, 1), f)
    ∇ℓ = ADgradient(:Flux, ℓ)
    x = randn(1)
    @test logdensity(Value, ℓ, x) ≅ logdensity(Value, ∇ℓ, x)
    @test logdensity(ValueGradient, ∇ℓ, x) ≅ ValueGradient(f(x), -6 .* x)
end

@testset "AD via ReverseDiff" begin
    f(x) = -3*abs2(x[1])
    ℓ = TransformedLogDensity(as(Array, asℝ, 1), f)
    ∇ℓ = ADgradient(:ReverseDiff, ℓ)
    ∇ℓt = ADgradient(:ReverseDiff, ℓ; tape = true)
    x = randn(1)
    @test logdensity(Value, ℓ, x) ≅ logdensity(Value, ∇ℓ, x) ≅ logdensity(Value, ∇ℓt, x)
    @test logdensity(ValueGradient, ∇ℓ, x) ≅ ValueGradient(f(x), -6 .* x) ≅
        logdensity(ValueGradient, ∇ℓt, x)
end

@testset "@iffinite" begin
    flag = [0]
    f(x) = (y = LogDensityProblems.@iffinite x; flag[1] += 1; y)
    @test f(NaN) ≡ NaN
    @test flag == [0]
    @test f(1) ≡ 1
    @test flag == [1]
end

@testset "rejection" begin
    f(x) = (z = first(x); z < 0 && reject_logdensity(); -abs2(z))
    P = TransformedLogDensity(as(Array, 1), f)
    @test logdensity(Value, P, [1.0]) ≅ Value(-1.0)
    @test logdensity(Value, P, [-1.0]) ≅ Value(-Inf)
    ∇P = ADgradient(:ForwardDiff, P)
    @test logdensity(Value, ∇P, [1.0]) ≅ Value(-1.0)
    @test logdensity(Value, ∇P, [-1.0]) ≅ Value(-Inf)
    @test logdensity(ValueGradient, ∇P, [1.0]) ≅ ValueGradient(-1.0, [-2.0])
    @test logdensity(ValueGradient, ∇P, [-1.0]) ≅ ValueGradient(-Inf, randn(1))
end

@testset "ADgradient missing method" begin
    msg = "Don't know how to AD with Foo, consider `import Foo` if there is such a package."
    P = TransformedLogDensity(as(Array, 1), x -> sum(abs2, x))
    @test_logs((:info, msg), @test_throws(MethodError, ADgradient(:Foo, P)))
end

@testset "reject wrapper" begin

    # function that throws various errors
    function f(x)
        y = first(x)
        if y > 1
            throw(DomainError(x))
        elseif y > 0
            throw(ArgumentError("bad"))
        elseif y > -1
            y
        else
            Inf
        end
    end
    x_dom = [1.5]
    x_arg = [0.5]
    x_inf = [-1.5]
    x_ok = [-0.5]

    # test unwrapped (for consistency)
    P = TransformedLogDensity(as(Array, 1), f)
    ∇P = ADgradient(:ForwardDiff, P)
    @test_throws InvalidLogDensityException(0, Inf) logdensity(Value, P, x_inf)
    @test_throws InvalidLogDensityException logdensity(ValueGradient, ∇P, x_inf)
    @test_throws ArgumentError logdensity(Value, P, x_arg)
    @test_throws ArgumentError logdensity(ValueGradient, ∇P, x_arg)
    @test_throws DomainError logdensity(Value, P, x_dom)
    @test_throws DomainError logdensity(ValueGradient, ∇P, x_dom)
    @test logdensity(Value, P, x_ok) ≅ Value(-0.5)
    @test logdensity(ValueGradient, ∇P, x_ok) ≅ ValueGradient(-0.5, [1.0])

    # test wrapped -- we catch domain and invalid log density errors
    R = LogDensityRejectErrors{Union{DomainError,InvalidLogDensityException}}(∇P)
    @test logdensity(Value, R, x_inf) ≅ logdensity(Value, R, x_dom) ≅ Value(-Inf)
    @test logdensity(ValueGradient, R, x_inf) ≅ logdensity(ValueGradient, R, x_dom) ≅
        ValueGradient(-Inf, x_inf)
    @test_throws ArgumentError logdensity(Value, R, x_arg)
    @test_throws ArgumentError logdensity(ValueGradient, R, x_arg)
    @test logdensity(Value, R, x_ok) ≅ Value(-0.5)
    @test logdensity(ValueGradient, R, x_ok) ≅ ValueGradient(-0.5, [1.0])

    # test constructor
    @test LogDensityRejectErrors{InvalidLogDensityException}(∇P) ≡
        LogDensityRejectErrors(∇P)
end