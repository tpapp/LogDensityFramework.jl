module LogDensityProblems

export logdensity, dimension, TransformedLogDensity, InvalidLogDensityException,
    reject_logdensity, LogDensityRejectErrors, ADgradient,
    get_transformation, get_parent # deprecated

using ArgCheck: @argcheck
using BenchmarkTools: @belapsed
using DocStringExtensions: SIGNATURES, TYPEDEF
import DiffResults
using Parameters: @unpack
using Random: AbstractRNG, GLOBAL_RNG
using Requires: @require

using TransformVariables: AbstractTransform, transform_logdensity, RealVector,
    TransformVariables, dimension, random_reals, random_arg

@deprecate get_parent(transformation) Base.parent(transformation)
@deprecate get_transformation(wrapper) wrapper.transformation

####
#### result types
####

"""
$(TYPEDEF)

Thrown when `Value` or `ValueGradient` is called with invalid arguments.
"""
struct InvalidLogDensityException{T} <: Exception
    "Location information: 0 is the value, positive integers are the gradient."
    index::Int
    "The invalid value."
    value::T
end

function Base.showerror(io::IO, ex::InvalidLogDensityException)
    @unpack index, value = ex
    print(io, "InvalidLogDensityException: ",
          index == 0 ? "value" : "gradient $(index)",
          " is $(value)")
end

struct Value{T <: Real}
    value::T
    function Value{T}(value::T) where {T <: Real}
        @argcheck (isfinite(value) || value == -Inf) InvalidLogDensityException(0, value)
        new{T}(value)
    end
end

"""
$(SIGNATURES)

Holds the value of a logdensity at a given point.

Constructor ensures that the value is either finite, or ``-∞``.

All other values (eg `NaN` or `Inf` for the `value`) lead to an error.

See also [`logdensity`](@ref).
"""
Value(value::T) where {T <: Real} = Value{T}(value)

Base.eltype(::Type{Value{T}}) where T = T

struct ValueGradient{T, V <: AbstractVector{T}}
    value::T
    gradient::V
    function ValueGradient{T,V}(value::T, gradient::V
                                ) where {T <: Real, V <: AbstractVector{T}}
        if value ≠ -Inf
            @argcheck isfinite(value) InvalidLogDensityException(0, value)
            invalid = findfirst(!isfinite, gradient)
            if invalid ≢ nothing
                throw(InvalidLogDensityException(invalid, gradient[invalid]))
            end
        end
        new{T,V}(value, gradient)
    end
end

"""
$(SIGNATURES)

Holds the value and gradient of a logdensity at a given point.

Constructor ensures that either

1. both the value and the gradient are finite,

2. the value is ``-∞`` (then gradient is not checked).

All other values (eg `NaN` or `Inf` for the `value`) lead to an error.

See also [`logdensity`](@ref).
"""
ValueGradient(value::T, gradient::V) where {T <: Real, V <: AbstractVector{T}} =
    ValueGradient{T,V}(value, gradient)

function ValueGradient(value::T1, gradient::AbstractVector{T2}) where {T1,T2}
    T = promote_type(T1, T2)
    ValueGradient(T(value), T ≡ T2 ? gradient : map(T, gradient))
end

Base.eltype(::Type{ValueGradient{T,V}}) where {T,V} = T

Base.isfinite(v::Union{Value, ValueGradient}) = isfinite(v.value)

Base.isinf(v::Union{Value, ValueGradient}) = isinf(v.value)

"""
$(TYPEDEF)

Exception for unwinding the stack early for infeasible values. Use `reject_logdensity()`.
"""
struct RejectLogDensity <: Exception end

"""
$(SIGNATURES)

Make wrappers return a `-Inf` log density (of the appropriate type).

!!! note

    This is done by throwing an exception that is caught by the wrappers, unwinding the
    stack. Using this function or returning `-Inf` is an implementation choice, do whatever
    is most convenient.
"""
reject_logdensity() = throw(RejectLogDensity())

####
#### interface for problems
####

"""
Abstract type for log density representations, which support the following
interface for `ℓ::AbstractLogDensityProblem`:

1. [`dimension`](@ref) returns the *dimension* of the domain of `ℓ`,

2. [`logdensity`](@ref) evaluates the log density `ℓ` at a given point.

See also [`LogDensityProblems.stresstest`](@ref) for stress testing.
"""
abstract type AbstractLogDensityProblem end

"""
    logdensity(resulttype, ℓ, x)

Evaluate the [`AbstractLogDensityProblem`](@ref) `ℓ` at `x`, which has length
compatible with its [`dimension`](@ref).

The argument `resulttype` determines the type of the result. [`Value`]@(ref)
results in the log density, while [`ValueGradient`](@ref) also calculates the
gradient, both returning eponymous types.
"""
function logdensity end

"""
    TransformedLogDensity(transformation, log_density_function)

A problem in Bayesian inference. Vectors of length `dimension(transformation)` are
transformed into a general object `θ` (unrestricted type, but a named tuple is recommended
for clean code), correcting for the log Jacobian determinant of the transformation.

It is recommended that `log_density_function` is a callable object that also encapsulates
the data for the problem.

`log_density_function(θ)` is expected to return *real numbers*. For zero densities or
infeasible `θ`s, `-Inf` or similar should be returned, but for efficiency of inference most
methods recommend using `transformation` to avoid this.

Use the property accessors `ℓ.transformation` and `ℓ.log_density_function` to access the
arguments of `ℓ::TransformedLogDensity`, these are part of the API.
"""
struct TransformedLogDensity{T <: AbstractTransform, L} <: AbstractLogDensityProblem
    transformation::T
    log_density_function::L
end

function Base.show(io::IO, ℓ::TransformedLogDensity)
    print(io, "TransformedLogDensity of dimension $(dimension(ℓ.transformation))")
end

"""
$(SIGNATURES)

The dimension of the problem, ie the length of the vectors in its domain.
"""
TransformVariables.dimension(p::TransformedLogDensity) = dimension(p.transformation)

function logdensity(::Type{Value}, p::TransformedLogDensity, x::RealVector)
    @unpack transformation, log_density_function = p
    try
        Value(transform_logdensity(transformation, log_density_function, x))
    catch e
        e isa RejectLogDensity || rethrow(e)
        Value(-Inf)
    end
end

####
#### wrappers — general
####

"""
An abstract type that wraps another log density in its field `ℓ`.

# Notes

Implementation detail, *not exported*.
"""
abstract type LogDensityWrapper <: AbstractLogDensityProblem end

Base.parent(w::LogDensityWrapper) = w.ℓ

TransformVariables.dimension(w::LogDensityWrapper) = dimension(parent(w))

####
#### wrappers -- convenience
####

struct LogDensityRejectErrors{E, L} <: LogDensityWrapper
    ℓ::L
end

"""
$(SIGNATURES)

Wrap a logdensity `ℓ` so that errors `<: E` are caught and replaced with a ``-∞`` value.

`E` defaults to `InvalidLogDensityExceptions`.

# Note

Use cautiously, as catching errors can mask errors in your code. The recommended use case is
for catching quirks and corner cases of AD. See also [`stresstest`](@ref) as an alternative
to using this wrapper.
"""
LogDensityRejectErrors{E}(ℓ::L) where {E,L} = LogDensityRejectErrors{E,L}(ℓ)

LogDensityRejectErrors(ℓ) = LogDensityRejectErrors{InvalidLogDensityException}(ℓ)

minus_inf_like(::Type{Value}, x) = Value(convert(eltype(x), -Inf))

minus_inf_like(::Type{ValueGradient}, x) = ValueGradient(convert(eltype(x), -Inf), similar(x))

function logdensity(kind, w::LogDensityRejectErrors{E}, x) where E
    try
        logdensity(kind, parent(w), x)
    catch e
        if e isa E
            minus_inf_like(kind, x)
        else
            rethrow(e)
        end
    end
end

"""
An abstract type that wraps another log density for calculating the gradient via AD.

Automatically defines a `logdensity(Value, ...)` method, subtypes should define a
`logdensity(ValueGradient, ...)` one.
"""
abstract type ADGradientWrapper <: LogDensityWrapper end

logdensity(::Type{Value}, fℓ::ADGradientWrapper, x::RealVector) =
    logdensity(Value, fℓ.ℓ, x)

"""
$(SIGNATURES)

Wrap `P` using automatic differentiation to obtain a gradient.

`kind` is usually a `Val` type, containing a symbol that refers to a package. The symbol can
also be used directly as eg

```julia
ADgradient(:ForwardDiff, P)
```

See `methods(ADgradient)`. Note that some methods are defined conditionally on the relevant
package being loaded.
"""
ADgradient(kind::Symbol, P; kwargs...) =
    ADgradient(Val{kind}(), P; kwargs...)

function ADgradient(v::Val{kind}, P; kwargs...) where kind
    @info "Don't know how to AD with $(kind), consider `import $(kind)` if there is such a package."
    throw(MethodError(ADgradient, (v, P)))
end

"""
$(SIGNATURES)

A closure for the value of the log density.
"""
@inline _value_closure(ℓ) = x -> logdensity(Value, ℓ, x).value

"""
$(SIGNATURES)

Make a vector argument for transformation `ℓ` using a Float64 vector.
"""
@inline _vectorargument(ℓ) = zeros(dimension(ℓ))

####
#### wrappers - specific
####

function __init__()
    @require ForwardDiff="f6369f11-7733-5829-9624-2563aa707210" include("AD_ForwardDiff.jl")
    @require Flux="587475ba-b771-5e3f-ad9e-33799f191a9c" include("AD_Flux.jl")
    @require ReverseDiff="37e2e3b7-166d-5795-8a7a-e32c996b4267" include("AD_ReverseDiff.jl")
end

####
#### stress testing
####

TransformVariables.random_arg(ℓ; kwargs...) = random_reals(dimension(ℓ); kwargs...)

"""
$(SIGNATURES)

Test `ℓ` with random values.

`N` random vectors are drawn from a standard multivariate Cauchy distribution, scaled with
`scale` (which can be a scalar or a conformable vector). In case the call produces an error,
the value is recorded as a failure, which are returned by the function.

Not exported, but part of the API.
"""
function stresstest(ℓ; N = 1000, rng::AbstractRNG = GLOBAL_RNG, scale = 1, resulttype = Value)
    failures = Vector{Float64}[]
    for _ in 1:N
        x = random_arg(ℓ; scale = scale, cauchy = true, rng = rng)
        try
            logdensity(resulttype, ℓ, x)
        catch e
            push!(failures, x)
        end
    end
    failures
end

####
#### utilities
####

"""
$(SIGNATURES)

If `expr` evaluates to a non-finite value, `return` with that, otherwise evaluate to that
value. Useful for returning early from non-finite likelihoods.

Part of the API, but not exported.
"""
macro iffinite(expr)
    quote
        result = $(esc(expr))
        isfinite(result) || return result
        result
    end
end

end # module
