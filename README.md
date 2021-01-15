# LogDensityProblems.jl

![Lifecycle](https://img.shields.io/badge/lifecycle-experimental-orange.svg)
![lifecycle](https://img.shields.io/badge/lifecycle-maturing-blue.svg)
[![build](https://github.com/tpapp/LogDensityProblems.jl/workflows/CI/badge.svg)](https://github.com/tpapp/LogDensityProblems.jl/actions?query=workflow%3ACI)
[![codecov.io](http://codecov.io/github/tpapp/LogDensityProblems.jl/coverage.svg?branch=master)](http://codecov.io/github/tpapp/LogDensityProblems.jl?branch=master)
[![Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://tpapp.github.io/LogDensityProblems.jl/stable)
[![Documentation](https://img.shields.io/badge/docs-master-blue.svg)](https://tpapp.github.io/LogDensityProblems.jl/dev)

A common framework for implementing and using log densities for inference, providing the following functionality.

1. The [`logdensity`](https://tamaspapp.eu/LogDensityProblems.jl/dev/#LogDensityProblems.logdensity) method with corresponding interface, which can be used by other packages that operate on (log) densities and need to evaluate the log densities or the gradients (eg [MCMC](https://en.wikipedia.org/wiki/Markov_chain_Monte_Carlo), [MAP](https://en.wikipedia.org/wiki/Maximum_a_posteriori_estimation), [ML](https://en.wikipedia.org/wiki/Maximum_likelihood_estimation) or similar methods).

2. The [`ADgradient`](https://tamaspapp.eu/LogDensityProblems.jl/dev/#LogDensityProblems.ADgradient) which makes objects that support `logdensity` to calculate log density *values* calculate log density *gradients* using various automatic differentiation packages.

3. The wrapper [`TransformedLogDensity`](https://tamaspapp.eu/LogDensityProblems.jl/dev/#LogDensityProblems.TransformedLogDensity) using the [TransformVariables.jl](https://github.com/tpapp/TransformVariables.jl) package, allowing callables that take a set of parameters transformed from a flat vector of real numbers to support the `logdensity` interface.

4. Various utility functions for debugging and testing log densities.

See the [documentation](https://tpapp.github.io/LogDensityProblems.jl/dev) for details.
