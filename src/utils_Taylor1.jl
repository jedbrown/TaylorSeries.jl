# utils_Taylor1.jl: 1-variable Taylor expansions
#
# Last modification: 2015.04.22
#
# Luis Benet & David P. Sanders
# UNAM
#


## Constructors ##
@doc """
DataType for polynomial expansions in one independent variable

Fieldnames:

- `coeffs`: vector containing the expansion coefficients; the i-th component is the i-1 coefficient of the expansion

- `order` : maximum order of the expansion considered

""" ->
immutable Taylor{T<:Number} <: AbstractSeries{T,1}
    coeffs :: Array{T,1}
    order :: Int

    ## Inner constructor ##
    function Taylor(coeffs::Array{T,1}, order::Int)
        lencoef = length(coeffs)
        order = max(order, lencoef-1)
        v = zeros(T, order+1)
        @inbounds for i in eachindex(coeffs)
            v[i] = coeffs[i]
        end
        new(v, order)
    end

end

## Outer constructors ##
Taylor{T<:Number}(x::Taylor{T}, order::Int) = Taylor{T}(x.coeffs, order)
Taylor{T<:Number}(x::Taylor{T}) = x
Taylor{T<:Number}(coeffs::Array{T,1}, order::Int) = Taylor{T}(coeffs, order)
Taylor{T<:Number}(coeffs::Array{T,1}) = Taylor{T}(coeffs, length(coeffs)-1)
Taylor{T<:Number}(x::T, order::Int) = Taylor{T}([x], order)
Taylor{T<:Number}(x::T) = Taylor{T}([x], 0)

## Type, length ##
eltype{T<:Number}(::Taylor{T}) = T
length{T<:Number}(a::Taylor{T}) = a.order

## Conversion and promotion rules ##
convert{T<:Number}(::Type{Taylor{T}}, a::Taylor) = Taylor(convert(Array{T,1}, a.coeffs), a.order)
convert{T<:Number, S<:Number}(::Type{Taylor{T}}, b::Array{S,1}) = Taylor(convert(Array{T,1},b))
convert{T<:Number}(::Type{Taylor{T}}, b::Number) = Taylor([convert(T,b)], 0)
promote_rule{T<:Number, S<:Number}(::Type{Taylor{T}}, ::Type{Taylor{S}}) = Taylor{promote_type(T, S)}
promote_rule{T<:Number, S<:Number}(::Type{Taylor{T}}, ::Type{Array{S,1}}) = Taylor{promote_type(T, S)}
promote_rule{T<:Number, S<:Number}(::Type{Taylor{T}}, ::Type{S}) = Taylor{promote_type(T, S)}

## Auxiliary function ##
function firstnonzero{T<:Number}(a::Taylor{T})
    order = a.order
    nonzero::Int = order+1
    z = zero(T)
    for i in eachindex(a.coeffs)
        if a.coeffs[i] != z
            nonzero = i-1
            break
        end
    end
    nonzero
end

function fixshape{T<:Number, S<:Number}(a::Taylor{T}, b::Taylor{S})
    if eltype(a) != eltype(b)
        a, b = promote(a, b)
    end
    if a.order < b.order
        a = Taylor(a, b.order)
    elseif a.order > b.order
        b = Taylor(b, a.order)
    end
    return a, b
end

## real, imag, conj and ctranspose ##
for f in (:real, :imag, :conj)
    @eval ($f){T<:Number}(a::Taylor{T}) = Taylor(($f)(a.coeffs), a.order)
end
ctranspose{T<:Number}(a::Taylor{T}) = conj(a)

## zero and one ##
zero{T<:Number}(a::Taylor{T}) = Taylor(zero(T), a.order)
one{T<:Number}(a::Taylor{T}) = Taylor(one(T), a.order)

## Equality ##
function ==(a::Taylor, b::Taylor)
    a, b = fixshape(a, b)
    return a.coeffs == b.coeffs
end

## Addition and substraction ##
for f in (:+, :-)
    @eval begin
        function ($f)(a::Taylor, b::Taylor)
            a, b = fixshape(a, b)
            v = similar(a.coeffs)
            @inbounds for i in eachindex(a.coeffs)
                v[i] = ($f)(a.coeffs[i], b.coeffs[i])
            end
            return Taylor(v, a.order)
        end
        ($f)(a::Taylor) = Taylor(($f)(a.coeffs), a.order)
    end
end

## Multiplication ##
function *(a::Taylor, b::Taylor)
    a, b = fixshape(a, b)
    T = eltype(a)
    coeffs = zeros(T,a.order+1)
    @inbounds coeffs[1] = a.coeffs[1] * b.coeffs[1]
    @inbounds for k = 1:a.order
        coeffs[k+1] = mulHomogCoef(k, a.coeffs, b.coeffs)
    end
    Taylor(coeffs, a.order)
end

# Homogeneous coefficient for the multiplication
function mulHomogCoef{T<:Number}(kcoef::Int, ac::Array{T,1}, bc::Array{T,1})
    kcoef == 0 && return ac[1] * bc[1]
    coefhomog = zero(T)
    @inbounds for i = 0:kcoef
        coefhomog += ac[i+1] * bc[kcoef-i+1]
    end
    coefhomog
end

## Division ##
function /(a::Taylor, b::Taylor)
    a, b = fixshape(a, b)
    orddivfact, cdivfact = divfactorization(a, b) # order and coefficient of first factorized term
    T = typeof(cdivfact)
    v1 = convert(Array{T,1}, a.coeffs)
    v2 = convert(Array{T,1}, b.coeffs)
    coeffs = zeros(T, a.order+1)
    @inbounds coeffs[1] = cdivfact
    @inbounds for k = orddivfact+1:a.order
        coeffs[k-orddivfact+1] = divHomogCoef(k, v1, v2, coeffs, orddivfact)
    end
    Taylor(coeffs, a.order)
end

function divfactorization(a1::Taylor, b1::Taylor)
    # order of first factorized term; a1 and b1 are assumed to be of the same order (length)
    a1nz = firstnonzero(a1)
    b1nz = firstnonzero(b1)
    orddivfact = min(a1nz, b1nz)
    if orddivfact > a1.order
        orddivfact = a1.order
    end
    cdivfact = a1.coeffs[orddivfact+1] / b1.coeffs[orddivfact+1]
    aux = abs2(cdivfact)

    # Is the polynomial factorizable?
    if isinf(aux) || isnan(aux)
        info("Order k=$(orddivfact) => coeff[$(orddivfact+1)]=$(cdivfact)")
        error("Division does not define a Taylor polynomial\n",
            " or its first non-zero coefficient is Inf/NaN.\n")
    ##else orddivfact>0
    ##    warn("Factorizing the polynomial.\n",
    ##        "The last k=$(orddivfact) Taylor coefficients ARE SET to 0.\n")
    end

    return orddivfact, cdivfact
end

# Homogeneous coefficient for the division
function divHomogCoef{T<:Number}(kcoef::Int, ac::Array{T,1}, bc::Array{T,1},
    coeffs::Array{T,1}, ordfact::Int)
    #
    @inbounds kcoef == ordfact && return ac[ordfact+1] / bc[ordfact+1]
    coefhomog = mulHomogCoef(kcoef, coeffs, bc)
    @inbounds coefhomog = (ac[kcoef+1]-coefhomog) / bc[ordfact+1]
    coefhomog
end

## Division functions: rem and mod
for op in (:mod, :rem)
    @eval begin
        function ($op){T<:Real}(a::Taylor{T}, x::Real)
            # coeffs = a.coeffs
            @inbounds a.coeffs[1] = ($op)(a.coeffs[1], x)
            return Taylor( a.coeffs, a.order)
        end
    end
end

function mod2pi{T<:Real}(a::Taylor{T})
    # coeffs = a.coeffs
    @inbounds a.coeffs[1] = mod2pi( a.coeffs[1] )
    return Taylor( a.coeffs, a.order)
end

## Int power ##
function ^{T<:Number}(a::Taylor{T}, n::Integer)
    n == 0 && return one(a)
    n == 1 && return a
    n == 2 && return square(a)
    n < 0 && return inv( a^(-n) )
    return power_by_squaring(a, n)
end

function ^{T<:Integer}(a::Taylor{T}, n::Integer)
    n == 0 && return one(a)
    n == 1 && return a
    n == 2 && return square(a)
    n < 0 && throw(DomainError())
    return power_by_squaring(a, n)
end

## power_by_squaring; slightly modified from base/intfuncs.jl
function power_by_squaring(x::Taylor, p::Integer)
    p == 1 && return copy(x)
    p == 0 && return one(x)
    p == 2 && return square(x)
    t = trailing_zeros(p) + 1
    p >>= t

    while (t -= 1) > 0
        x = square(x)
    end

    y = x
    while p > 0
        t = trailing_zeros(p) + 1
        p >>= t
        while (t -= 1) >= 0
            x = square(x)
        end
        y *= x
    end

    return y
end

## Rational power ##
^(a::Taylor,x::Rational) = a^(x.num/x.den)

## Real power ##
function ^(a::Taylor, x::Real)
    uno = one(a)
    x == zero(x) && return uno
    x == one(x)/2 && return sqrt(a)
    isinteger(x) && return a^int(x)
    order = a.order

    # First non-zero coefficient
    l0nz = firstnonzero(a)
    l0nz > order && return zero(a)

    # The first non-zero coefficient of the result; must be integer
    lnull = x*l0nz
    !isinteger(lnull) &&
        error("Integer exponent REQUIRED if the Taylor polynomial is expanded around 0.\n")

    # Reaching this point, it is possible to implement the power of the Taylor polynomial.
    # The last l0nz coefficients are set to zero.
    lnull = trunc(Int,lnull)
    ##l0nz > 0 && warn("The last k=$(l0nz) Taylor coefficients ARE SET to 0.\n")
    @inbounds aux = (a.coeffs[l0nz+1])^x
    T = typeof(aux)
    v = convert(Array{T,1}, a.coeffs)
    coeffs = zeros(T, order+1)
    @inbounds coeffs[lnull+1] = aux
    k0 = lnull+l0nz
    @inbounds for k = k0+1:order
        coeffs[k-l0nz+1] = powHomogCoef(k, v, x, coeffs, l0nz)
    end

    Taylor(coeffs,order)
end

# Homogeneous coefficients for real power
function powHomogCoef{T<:Number}(kcoef::Int, ac::Array{T,1}, x::Real,
    coeffs::Array{T,1}, knull::Int)

    kcoef == knull && return (ac[knull+1])^x
    coefhomog = zero(T)
    for i = 0:kcoef-knull-1
        aux = x*(kcoef-i)-i
        @inbounds coefhomog += aux*ac[kcoef-i+1]*coeffs[i+1]
    end
    aux = kcoef - knull*(x+1)
    @inbounds coefhomog = coefhomog / (aux*ac[knull+1])

    coefhomog
end
^(a::Taylor, x::Complex) = exp( x*log(a) )
^(a::Taylor, b::Taylor) = exp( b*log(a) )

## Square ##
function square(a::Taylor)
    order = a.order
    T = eltype(a)
    coeffs = zeros(T,order+1)
    coeffs[1] = a.coeffs[1]^2
    @inbounds for k = 1:order
        coeffs[k+1] = squareHomogCoef(k, a.coeffs)
    end
    Taylor(coeffs,order)
end

# Homogeneous coefficients for square
function squareHomogCoef{T<:Number}(kcoef::Int, ac::Array{T,1})
    kcoef == 0 && return ac[1]^2
    coefhomog = zero(T)
    kodd = kcoef%2
    kend = div(kcoef - 2 + kodd, 2)
    @inbounds for i = 0:kend
        coefhomog += ac[i+1]*ac[kcoef-i+1]
    end
    coefhomog = 2coefhomog
    if kodd == 0
        @inbounds coefhomog += ac[div(kcoef,2)+1]^2
    end
    coefhomog
end

## Square root ##
function sqrt(a::Taylor)
    order = a.order
    # First non-zero coefficient
    l0nz = firstnonzero(a)
    if l0nz > order
        return zero(a)
    elseif l0nz%2 == 1 # l0nz must be pair
        error("First non-vanishing Taylor coefficient must be an EVEN POWER\n",
            "to expand SQRT around 0.\n")
    end

    # Reaching this point, it is possible to implement the sqrt of the Taylor polynomial.
    # The last l0nz coefficients are set to zero.
    ##l0nz > 0 && warn("The last k=$(l0nz) Taylor coefficients ARE SET to 0.\n")
    lnull = div(l0nz, 2)
    @inbounds aux = sqrt(a.coeffs[l0nz+1])
    T = typeof(aux)
    v = convert(Array{T,1}, a.coeffs)
    coeffs = zeros(T, order+1)
    @inbounds coeffs[lnull+1] = aux
    @inbounds for k = lnull+1:order-l0nz
        coeffs[k+1] = sqrtHomogCoef(k, v, coeffs, lnull)
    end
    Taylor(coeffs, order)
end

# Homogeneous coefficients for the square-root
function sqrtHomogCoef{T<:Number}(kcoef::Int, ac::Array{T,1}, coeffs::Array{T,1}, knull::Int)
    kcoef == knull && return sqrt(ac[2*knull+1])
    coefhomog = zero(T)
    kodd = (kcoef - knull)%2
    kend = div(kcoef - knull - 2 + kodd, 2)
    @inbounds for i = knull+1:knull+kend
        coefhomog += coeffs[i+1]*coeffs[kcoef+knull-i+1]
    end
    @inbounds aux = ac[kcoef+knull+1]-2coefhomog

    if kodd == 0
        @inbounds aux = aux - (coeffs[kend+knull+2])^2
    end
    @inbounds coefhomog = aux / (2coeffs[knull+1])

    coefhomog
end

## Exp ##
function exp(a::Taylor)
    order = a.order
    @inbounds aux = exp( a.coeffs[1] )
    T = typeof(aux)
    v = convert(Array{T,1}, a.coeffs)
    coeffs = zeros(T, order+1)
    @inbounds coeffs[1] = aux
    @inbounds for k = 1:order
        coeffs[k+1] = expHomogCoef(k, v, coeffs)
    end
    Taylor( coeffs, order )
end

# Homogeneous coefficients for exp
function expHomogCoef{T<:Number}(kcoef::Int, ac::Array{T,1}, coeffs::Array{T,1})
    kcoef == 0 && return exp(ac[1])
    coefhomog = zero(T)
    @inbounds for i = 0:kcoef-1
        coefhomog += (kcoef-i) * ac[kcoef-i+1] * coeffs[i+1]
    end
    coefhomog = coefhomog/kcoef
    coefhomog
end

## Log ##
function log(a::Taylor)
    order = a.order
    l0nz = firstnonzero(a)
    if firstnonzero(a)>0
        error("Not possible to expand LOG around 0.\n")
    end
    @inbounds aux = log( a.coeffs[1] )
    T = typeof(aux)
    ac = convert(Array{T,1}, a.coeffs)
    coeffs = zeros(T, order+1)
    @inbounds coeffs[1] = aux
    @inbounds for k = 1:order
        coeffs[k+1] = logHomogCoef(k, ac, coeffs)
    end
    Taylor( coeffs, order )
end

# Homogeneous coefficients for log
function logHomogCoef{T<:Number}(kcoef::Int, ac::Array{T,1}, coeffs::Array{T,1})
    kcoef == 0 && return log( ac[1] )
    coefhomog = zero(T)
    @inbounds for i = 1:kcoef-1
        coefhomog += (kcoef-i) * ac[i+1] * coeffs[kcoef-i+1]
    end
    @inbounds coefhomog = (ac[kcoef+1] -coefhomog/kcoef) / ac[1]
    coefhomog
end

## Sin and cos ##
sin(a::Taylor) = sincos(a)[1]
cos(a::Taylor) = sincos(a)[2]
function sincos(a::Taylor)
    order = a.order
    @inbounds aux = sin( a.coeffs[1] )
    T = typeof(aux)
    v = convert(Array{T,1}, a.coeffs)
    sincoeffs = zeros(T,order+1)
    coscoeffs = zeros(T,order+1)
    @inbounds sincoeffs[1] = aux
    @inbounds coscoeffs[1] = cos( a.coeffs[1] )
    @inbounds for k = 1:order
        sincoeffs[k+1], coscoeffs[k+1] = sincosHomogCoef(k, v, sincoeffs, coscoeffs)
    end
    return Taylor(sincoeffs, order), Taylor(coscoeffs, order)
end

# Homogeneous coefficients for sincos
function sincosHomogCoef{T<:Number}(kcoef::Int, ac::Array{T,1},
    scoeffs::Array{T,1}, ccoeffs::Array{T,1})

    kcoef == 0 && return sin( ac[1] ), cos( ac[1] )
    sincoefhom = zero(T)
    coscoefhom = zero(T)

    @inbounds for i = 1:kcoef
            x = i * ac[i+1]
            sincoefhom += x * ccoeffs[kcoef-i+1]
            coscoefhom -= x * scoeffs[kcoef-i+1]
    end

    sincoefhom = sincoefhom/kcoef
    coscoefhom = coscoefhom/kcoef
    return sincoefhom, coscoefhom
end

## Tan ##
function tan(a::Taylor)
    order = a.order
    aux = tan( a.coeffs[1] )
    T = typeof(aux)
    v = convert(Array{T,1}, a.coeffs)
    coeffs = zeros(T,order+1)
    coeffst2 = zeros(T,order+1)
    @inbounds coeffs[1] = aux
    @inbounds coeffst2[1] = aux^2
    @inbounds for k = 1:order
        coeffs[k+1] = tanHomogCoef(k, v, coeffst2)
        coeffst2[k+1] = squareHomogCoef(k, coeffs)
    end
    Taylor( coeffs, order )
end
# Homogeneous coefficients for tan
function tanHomogCoef{T<:Number}(kcoef::Int, ac::Array{T,1}, coeffst2::Array{T,1})
    kcoef == 0 && return tan( ac[1] )
    coefhomog = zero(T)
    @inbounds for i = 0:kcoef-1
        coefhomog += (kcoef-i)*ac[kcoef-i+1]*coeffst2[i+1]
    end
    @inbounds coefhomog = ac[kcoef+1] + coefhomog/kcoef
    coefhomog
end

## Differentiating ##
function diffTaylor(a::Taylor)
    order = a.order
    coeffs = zero(a.coeffs)
    @inbounds coeffs[1] = a.coeffs[2]
    @inbounds for i = 1:order
        coeffs[i] = i*a.coeffs[i+1]
    end
    return Taylor(coeffs, order)
end

## Integrating ##
function integTaylor{T<:Number}(a::Taylor{T}, x::Number)
    order = a.order
    R = promote_type(T, typeof(a.coeffs[1] / 1), typeof(x))
    coeffs = zeros(R, order+1)
    @inbounds for i = 1:order
        coeffs[i+1] = a.coeffs[i] / i
    end
    @inbounds coeffs[1] = convert(R, x)
    return Taylor(coeffs, order)
end
integTaylor{T<:Number}(a::Taylor{T}) = integTaylor(a, zero(T))

## Evaluates a Taylor polynomial on a given point using Horner's rule ##
function evalTaylor{T<:Number,S<:Number}(a::Taylor{T}, dx::S)
    R = promote_type(T,S)
    orden = a.order
    @inbounds suma = convert(R, a.coeffs[end])
    @inbounds for k = orden:-1:1
        suma = suma*dx + a.coeffs[k]
    end
    suma
end
evalTaylor{T<:Number}(a::Taylor{T}) = evalTaylor(a, zero(T))

function evalTaylor{T<:Number,S<:Number}(a::Taylor{T}, x::Taylor{S})
    a, x = fixshape(a, x)
    @inbounds suma = a.coeffs[end]
    @inbounds for k = a.order:-1:1
        suma = suma*x + a.coeffs[k]
    end
    suma
end

## Returns de n-th derivative of a series expansion
function deriv{T}(a::Taylor{T}, n::Int=1)
    @assert n>= 0
    n > a.order && error(
        "You need to increase the order of the Taylor series (currently ", a.order, ")\n",
        "to calculate its ", n,"-th derivative.")
    res::T = factorial( widen(n) ) * a.coeffs[n+1]
    return res
end
