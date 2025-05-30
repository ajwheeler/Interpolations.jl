For a comprehensive list of changes, see [Releases](https://github.com/JuliaMath/Interpolations.jl/releases).

# v0.16

Breaking changes:
- `getindex` for AbstractInterpolations only accepts integers ([#579](https://github.com/JuliaMath/Interpolations.jl/pull/579)), deprecated since ([#226](https://github.com/JuliaMath/Interpolations.jl/pull/226))
- `gradient` and `hessian` are once again no longer exported ([#623](https://github.com/JuliaMath/Interpolations.jl/pull/623))
- Fix free boundary condition on `Cubic` ([#616](https://github.com/JuliaMath/Interpolations.jl/pull/616))
- Compatible with Julia versions 1.9 and later

# v0.15

Breaking changes:
- Compatible with Julia versions 1.6 and later

# v0.14.0

Breaking changes:

## Implement inplace `GriddedInterpolation` ([#496](https://github.com/JuliaMath/Interpolations.jl/pull/496), for [#495](https://github.com/JuliaMath/Interpolations.jl/issues/495))
- `interpolate` now copies the coefficients for `GriddedInterpolation`.
- `interpolate!` now does not copy the coefficients for `GriddedInterpolation`.
- The third argument of `GriddedInterpolation` describes the array type of the coefficients rather than the element type of `Array`.

# v0.9.0

Breaking changes:

- `gradient` and `hessian` are no longer exported; use `Interpolations.gradient` and
  `Interpolations.hessian`.
- `interpolate` objects now check bounds, and throw an error if you try to evaluate them
  at locations beyond the edge of their interpolation domain; use `extrapolate` if you need out-of-bounds evaluation
- For quadratic and cubic interpolation, `interpolate!` now returns an object whose axes
  are narrowed by the amount of padding needed on the array edges. This preserves correspondence
  between input indices and output indices. See https://julialang.org/blog/2017/04/offset-arrays
  for more information.
- The parametrization of some types has changed; this does not affect users of the "exported"
  interface, but does break packages that performed manual construction of explicit types.

Changes with deprecation warnings:

- `itp[i...]` should be replaced with `itp(i...)`.
- `OnGrid` and `OnCell` should now be placed inside the boundary condition (e.g., `Flat(OnGrid())`),
  and should only be used for quadratic and cubic interpolation.
- the extrapolation boundary condition `Linear` was changed to `Line`, to be consistent
  with interpolation boundary conditions.

Advance notice of future changes:

- In future versions `itp[i...]` may be interpreted with reference to the parent array's
  indices rather than the knots supplied by the user (relevant for `scale` and `Gridded`).
  If you fix the existing deprecation warnings then you should be prepared for this change.
