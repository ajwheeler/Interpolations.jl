### Primary evaluation entry points (itp(x...), gradient(itp, x...), and hessian(itp, x...))

itpinfo(itp) = (tcollect(itpflag, itp), axes(itp))

@inline function (itp::BSplineInterpolation{T,N})(x::Vararg{Number,N}) where {T,N}
    @boundscheck (checkbounds(Bool, itp, just_dual_value.(x)...) || Base.throw_boundserror(itp, x))
    wis = weightedindexes((value_weights,), itpinfo(itp)..., x)
    InterpGetindex(itp)[wis...]
end
@propagate_inbounds function (itp::BSplineInterpolation{T,N})(x::Vararg{Number,M}) where {T,M,N}
    inds, trailing = split_trailing(itp, x)
    @boundscheck (check1(trailing) || Base.throw_boundserror(itp, x))
    @assert length(inds) == N
    itp(inds...)
end
@inline function (itp::BSplineInterpolation{T,N})(x::Vararg{Union{Number,AbstractVector},N}) where {T,N}
    @boundscheck (checkbounds(Bool, itp, x...) || Base.throw_boundserror(itp, x))
    itps = tcollect(itpflag, itp)
    wis = dimension_wis(value_weights, itps, axes(itp), x)
    coefs = InterpGetindex(itp)
    ret = [coefs[i...] for i in Iterators.product(wis...)]
    reshape(ret, shape(wis...))
end

@propagate_inbounds function gradient(itp::BSplineInterpolation{T,N}, x::Vararg{Number,N}) where {T,N}
    @boundscheck checkbounds(Bool, itp, x...) || Base.throw_boundserror(itp, x)
    wis = weightedindexes((value_weights, gradient_weights), itpinfo(itp)..., x)
    return SVector(_gradient(InterpGetindex(itp), wis...))   # work around #311
end
@inline _gradient(coefs, inds, moreinds...) = (coefs[inds...], _gradient(coefs, moreinds...)...)
_gradient(coefs) = ()

@propagate_inbounds function gradient!(dest, itp::BSplineInterpolation{T,N}, x::Vararg{Number,N}) where {T,N}
    dest .= gradient(itp, x...)
end

@propagate_inbounds function hessian(itp::BSplineInterpolation{T,N}, x::Vararg{Number,N}) where {T,N}
    @boundscheck checkbounds(Bool, itp, x...) || Base.throw_boundserror(itp, x)
    wis = weightedindexes((value_weights, gradient_weights, hessian_weights), itpinfo(itp)..., x)
    symmatrix(map(inds->InterpGetindex(itp)[inds...], wis))
end
@propagate_inbounds function hessian!(dest, itp::BSplineInterpolation{T,N}, x::Vararg{Number,N}) where {T,N}
    dest .= hessian(itp, x...)
end

# Leftovers from AbstractInterpolation
@inline function (itp::BSplineInterpolation)(x::Vararg{UnexpandedIndexTypes})
    itp(to_indices(itp, x)...)
end
@inline function (itp::BSplineInterpolation)(x::Vararg{ExpandedIndexTypes})
    itp.(Iterators.product(x...))
end

"""
    weightedindexes(fs, itpflags, nodes, xs)

Compute `WeightedIndex` values for evaluation at the position `xs...`.
`fs` is a function or tuple of functions indicating the types of index required,
typically `value_weights`, `gradient_weights`, and/or `hessian_weights`.
`itpflags` and `nodes` can be obtained from `itpinfo(itp)...`.

See the "developer documentation" for further information.
"""
@inline function weightedindexes(fs::F, itpflags::NTuple{N,Flag}, knots::NTuple{N,AbstractVector}, xs::NTuple{N,Number}) where {F,N}
    # parts = map((flag, knotvec, x)->weightedindex_parts(fs, flag, knotvec, x), itpflags, knots, xs)
    parts = map3argf(weightedindex_parts, fs, itpflags, knots, xs)
    weightedindexes(parts...)
end
# This is a force-inlined version of map((flag, knotvec, x)->g(fs, flag, knotvec, x), itpflags, knots, xs)
@inline map3argf(g::G, fs::F, itpflags, knots, xs) where {G,F} =
    (g(fs, itpflags[1], knots[1], xs[1]), map3argf(g, fs, Base.tail(itpflags), Base.tail(knots), Base.tail(xs))...)
map3argf(g::G, fs::F, ::Tuple{}, ::Tuple{}, ::Tuple{}) where {G,F} = ()

weightedindexes(i::Vararg{Int,N}) where N = i  # the all-NoInterp case

const PositionCoefs{P,C} = NamedTuple{(:position,:coefs),Tuple{P,C}}
const ValueParts{P,W} = PositionCoefs{P,Tuple{W}}
@inline weightedindexes(parts::Vararg{Union{Int,ValueParts},N}) where N =
    map(maybe_weightedindex, map(positions, parts), map(valuecoefs, parts))
maybe_weightedindex(i::Integer, _::Integer) = Int(i)
maybe_weightedindex(pos, coefs::Tuple) = WeightedIndex(pos, coefs)

positions(i::Int) = i
valuecoefs(i::Int) = i
gradcoefs(i::Int) = i
hesscoefs(i::Int) = i
positions(t::PositionCoefs) = t.position
valuecoefs(t::PositionCoefs) = t.coefs[1]
gradcoefs(t::PositionCoefs) = t.coefs[2]
hesscoefs(t::PositionCoefs) = t.coefs[3]

const GradParts{P,W1,W2} = PositionCoefs{P,Tuple{W1,W2}}
function weightedindexes(parts::Vararg{Union{Int,GradParts},N}) where N
    # Create (wis1, wis2, ...) where wisn is used to evaluate the gradient along the nth *chosen* dimension
    # Example: if itp is a 3d interpolation of form (Linear, NoInterp, Quadratic) then we will return
    #    (gwi1, i2, wi3), (wi1, i2, gwi3)
    # where wik are value-coefficient WeightedIndexes along dimension k
    #       gwik are gradient-coefficient WeightedIndexes along dimension k
    #       i2 is the integer index along dimension 2
    # These will result in a 2-vector gradient.
    # TODO: check whether this is inferable
    slot_substitute(parts, map(positions, parts), map(valuecoefs, parts), map(gradcoefs, parts))
end

# Substitute the dth dimension's gradient coefs for the remaining coefs
function slot_substitute(kind, p, v, g)
    rest = slot_substitute(Base.tail(kind), p, v, g)
    kind[1] isa Int && return rest # Skip over NoInterp dimensions
    (map(maybe_weightedindex, p, substitute_ruled(v, kind, g)), rest...)
end
# Termination
slot_substitute(kind::Tuple{}, p, v, g) = ()

const HessParts{P,W1,W2,W3} = PositionCoefs{P,Tuple{W1,W2,W3}}
function weightedindexes(parts::Vararg{Union{Int,HessParts},N}) where N
    # Create (wis1, wis2, ...) where wisn is used to evaluate the nth *chosen* hessian component
    # Example: if itp is a 3d interpolation of form (Linear, NoInterp, Quadratic) then we will return
    #    (hwi1, i2, wi3), (gwi1, i2, gwi3), (wi1, i2, hwi3)
    # where wik are value-coefficient WeightedIndexes along dimension k
    #       gwik are 1st-derivative WeightedIndexes along dimension k
    #       hwik are 2nd-derivative WeightedIndexes along dimension k
    #       i2 is just the index along dimension 2
    # These will result in a 2x2 hessian [hc1 hc2; hc2 hc3] where
    #    hc1 = coefs[hwi1, i2, wi3]
    #    hc2 = coefs[gwi1, i2, gwi3]
    #    hc3 = coefs[wi1,  i2, hwi3]
    slot_substitute(parts, map(positions, parts), map(valuecoefs, parts), map(gradcoefs, parts), map(hesscoefs, parts))
end
# Substitute the dth dimension's gradient coefs for the remaining coefs, column by column
slot_substitute(kind::Tuple, p, v, g, h) = (_column(kind, kind, p, v, g, h)..., slot_substitute(Base.tail(kind), p, v, g, h)...)
slot_substitute(::Tuple{}, p, v, g, h) = ()
# inner: calculate a single column
function _column(kind1::K, kind2::K, p, v, g, h) where {K<:Tuple}
    ss = substitute_ruled(v, kind1, h)
    (map(maybe_weightedindex, p, ss), _column(Base.tail(kind1), kind2, p, v, g, h)...)
end
_column(kind1::K, kind2::K, p, v, g, h) where {K<:Tuple{Int,Vararg}} = () # Skip over NoInterp dimensions
function _column(kind1::Tuple, kind2::Tuple, p, v, g, h)
    rest = _column(Base.tail(kind1), kind2, p, v, g, h)
    kind1[1] isa Int && return rest # Skip over NoInterp dimensions
    ss = substitute_ruled(substitute_ruled(v, kind1, g), kind2, g)
    (map(maybe_weightedindex, p, ss), rest...)
end
_column(::Tuple{}, ::Tuple, p, v, g, h) = ()

weightedindex_parts(fs::F, itpflag::BSpline, ax, x) where F =
    weightedindex_parts(fs, degree(itpflag), ax, x)

function weightedindex_parts(fs::F, deg::Degree, ax::AbstractUnitRange{<:Integer}, x) where F
    pos, δx = positions(deg, ax,  x)
    (position=pos, coefs=fmap(fs, deg, δx))
end


# there is a Heisenbug, when Base.promote_op is inlined into getindex_return_type
# thats why we use this @noinline fence
@noinline _promote_mul(a,b) = Base.promote_op(*, a, b)

@noinline function getindex_return_type(::Type{BSplineInterpolation{T,N,TCoefs,IT,Axs}}, argtypes::Tuple) where {T,N,TCoefs,IT<:DimSpec{BSpline},Axs}
    reduce(_promote_mul, eltype(TCoefs), argtypes)
end

function getindex_return_type(::Type{BSplineInterpolation{T,N,TCoefs,IT,Axs}}, ::Type{I}) where {T,N,TCoefs,IT<:DimSpec{BSpline},Axs,I}
    _promote_mul(eltype(TCoefs), I)
end

# This handles round-towards-the-middle for points on half-integer edges
roundbounds(x::Integer, bounds::Tuple{Real,Real}) = x
roundbounds(x::Integer, bounds::AbstractUnitRange) = x
roundbounds(x::Number, bounds::Tuple{Real,Real}) = _roundbounds(x, bounds)
roundbounds(x::Number, bounds::AbstractUnitRange) = _roundbounds(x, bounds)
function _roundbounds(x::Number, bounds::Union{Tuple{Real,Real}, AbstractUnitRange})
    l, u = first(bounds), last(bounds)
    h = half(x)
    xh = x+h
    ifelse(x < u+half(u), floor(xh), ceil(xh)-1)
end

floorbounds(x::Integer, ax::Tuple{Real,Real}) = x
floorbounds(x::Integer, ax::AbstractUnitRange) = x
floorbounds(x, ax::Tuple{Real,Real}) = _floorbounds(x, ax)
floorbounds(x, ax::AbstractUnitRange) = _floorbounds(x, ax)
function _floorbounds(x, ax::Union{Tuple{Real,Real}, AbstractUnitRange})
    l = first(ax)
    h = half(x)
    ifelse(x < l, floor(x+h), floor(x+zero(h)))
end

ceilbounds(x::Integer, ax::Tuple{Real,Real}) = x
ceilbounds(x::Integer, ax::AbstractUnitRange) = x
ceilbounds(x, ax::Tuple{Real,Real}) = _ceilbounds(x, ax)
ceilbounds(x, ax::AbstractUnitRange) = _ceilbounds(x, ax)
function _ceilbounds(x, ax::Union{Tuple{Real,Real}, AbstractUnitRange})
    u = last(ax)
    h = half(x)
    ifelse(x > u, ceil(x+h), ceil(x+zero(h)))
end

half(x) = oneunit(x)/2

symmatrix(h::NTuple{1,Any}) = SMatrix{1,1}(h)
symmatrix(h::NTuple{3,Any}) = SMatrix{2,2}((h[1], h[2], h[2], h[3]))
symmatrix(h::NTuple{6,Any}) = SMatrix{3,3}((h[1], h[2], h[3], h[2], h[4], h[5], h[3], h[5], h[6]))
function symmatrix(h::NTuple{L,Any}) where L
    N = symsize(Val(L))
    l = MMatrix{N,N,Int}(undef)
    l[:,1] = 1:N
    idx = N
    for j = 2:N, i = 1:N
        if i < j
            l[i,j] = l[j,i]
        else
            l[i,j] = (idx+=1)
        end
    end
    if @generated
        hexprs = [:(h[$i]) for i in vec(l)]
        :(SMatrix{$N,$N}($(hexprs...,)))
    else
        SMatrix{N,N}(h[i] for i in l)
    end
end

# Use @generated to force const propagation
@generated function symsize(::Val{L}) where L
    N = floor(Int, sqrt(2L))
    (N*(N+1))÷2 == L || error("$L must be equal to N*(N+1)/2 (N = $N)")
    return :($N)
end
