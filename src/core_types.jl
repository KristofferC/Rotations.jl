"""
    abstract Rotation{N,T} <: StaticMatrix{T}

An abstract type representing `N`-dimensional rotations. More abstractly, they represent
unitary (orthogonal) `N`×`N` matrices.
"""
abstract Rotation{N,T} <: StaticMatrix{T}

Base.@pure Base.size{N}(::Type{Rotation{N}}) = (N,N)
Base.@pure Base.size{N,T}(::Type{Rotation{N,T}}) = (N,N)
Base.@pure Base.size{R<:Rotation}(::Type{R}) = size(supertype(R))
size(r::Rotation) = size(typeof(r))
Base.ctranspose(r::Rotation) = inv(r)
Base.transpose{N,T<:Real}(r::Rotation{N,T}) = inv(r)

# Rotation angles and axes can be obtained by converting to the AngleAxis type
rotation_angle(r::Rotation) = rotation_angle(AngleAxis(r))
rotation_axis(r::Rotation) = rotation_axis(AngleAxis(r))

# Rotation matrices should be orthoginal/unitary. Only the operations we define,
# like multiplication, will stay as Rotations, otherwise users will get an
# SMatrix{3,3} (e.g. rot1 + rot2 -> SMatrix)
Base.@pure StaticArrays.similar_type{R <: Rotation}(::Union{R,Type{R}}) = SMatrix{size(R)..., eltype(R), prod(size(R))}
Base.@pure StaticArrays.similar_type{R <: Rotation, T}(::Union{R,Type{R}}, ::Type{T}) = SMatrix{size(R)..., T, prod(size(R))}

function Base.rand{R <: Rotation{2}}(::Type{R})
    T = eltype(R)
    if T == Any
        T = Float64
    end

    R(2π * rand(T))
end

# A random rotation can be obtained easily with unit quaternions
# The unit sphere in R⁴ parameterizes quaternion rotations according to the
# Haar measure of SO(3) - see e.g. http://math.stackexchange.com/questions/184086/uniform-distributions-on-the-space-of-rotations-in-3d
function Base.rand{R <: Rotation{3}}(::Type{R})
    T = eltype(R)
    if T == Any
        T = Float64
    end

    q = Quat(randn(T), randn(T), randn(T), randn(T))
    return R(q)
end

# Useful for converting arrays of rotations to another rotation eltype, for instance.
# Only works because parameters of all the rotations are of a similar form
# Would need to be more sophisticated if we have arbitrary dimensions, etc
@inline function Base.promote_op{R1 <: Rotation, R2 <: Rotation}(::Type{R1}, ::Type{R2})
    size(R1) == size(R2) || throw(DimensionMismatch("cannot promote rotations of $(size(R1)[1]) and $(size(R2)[1]) dimensions"))
    if isleaftype(R1)
        return R1
    else
        return R1{eltype(R2)}
    end
end

@inline function Base.:/(r1::Rotation, r2::Rotation)
    r1 * inv(r2)
end

@inline function Base.:\(r1::Rotation, r2::Rotation)
    inv(r1) * r2
end

################################################################################
################################################################################
"""
    immutable RotMatrix{N,T} <: Rotation{N,T}

A statically-sized, N×N unitary (orthogonal) matrix.

Note: the orthonormality of the input matrix is *not* checked by the constructor.
"""
immutable RotMatrix{N,T,L} <: Rotation{N,T} # which is <: AbstractMatrix{T}
    mat::SMatrix{N, N, T, L} # The final parameter to SMatrix is the "length" of the matrix, 3 × 3 = 9
end

# These functions (plus size) are enough to satisfy the entire StaticArrays interface:
# @inline (::Type{R}){R<:RotMatrix}(t::Tuple)  = error("No precise constructor found. Length of input was $(length(t)).")
for N = 2:3
    L = N*N
    @eval begin
        @inline (::Type{RotMatrix})(t::NTuple{$L})  = RotMatrix(SMatrix{$N,$N}(t))
        @inline (::Type{RotMatrix{$N}})(t::NTuple{$L}) = RotMatrix(SMatrix{$N,$N}(t))
        @inline (::Type{RotMatrix{$N,T}}){T}(t::NTuple{$L}) = RotMatrix(SMatrix{$N,$N,T}(t))
        @inline (::Type{RotMatrix{$N,T,$L}}){T}(t::NTuple{$L}) = RotMatrix(SMatrix{$N,$N,T}(t))
    end
end
Base.@propagate_inbounds Base.getindex(r::RotMatrix, i::Integer) = r.mat[i]

@inline (::Type{RotMatrix})(θ::Real) = RotMatrix(@SMatrix [cos(θ) -sin(θ); sin(θ) cos(θ)])
@inline (::Type{RotMatrix{2}})(θ::Real)      = RotMatrix(@SMatrix [cos(θ) -sin(θ); sin(θ) cos(θ)])
@inline (::Type{RotMatrix{2,T}}){T}(θ::Real) = RotMatrix(@SMatrix T[cos(θ) -sin(θ); sin(θ) cos(θ)])

# A rotation is more-or-less defined as being an orthogonal (or unitary) matrix
Base.inv(r::RotMatrix) = RotMatrix(r.mat')

# A useful constructor for identity rotation (eye is already provided by StaticArrays, but needs an eltype)
@inline Base.eye{N}(::Type{RotMatrix{N}}) = RotMatrix((eye(SMatrix{N,N,Float64})))
@inline Base.eye{N,T}(::Type{RotMatrix{N,T}}) = RotMatrix((eye(SMatrix{N,N,T})))

# By default, composition of rotations will go through RotMatrix, unless overridden
@inline *(r1::Rotation, r2::Rotation) = RotMatrix(r1) * RotMatrix(r2)
@inline *(r1::RotMatrix, r2::Rotation) = r1 * RotMatrix(r2)
@inline *(r1::Rotation, r2::RotMatrix) = RotMatrix(r1) * r2
@inline *(r1::RotMatrix, r2::RotMatrix) = RotMatrix(r1.mat * r2.mat) # TODO check that this doesn't involve extra copying.

################################################################################
################################################################################

"""
    isrotation(r)
    isrotation(r, tol)

Check whether `r` is a 3×3 rotation matrix, where `r * r'` is within `tol` of
the identity matrix (using the Frobenius norm). (`tol` defaults to
`1000 * eps(eltype(r))`.)
"""
function isrotation{T}(r::AbstractMatrix{T}, tol::Real = 1000 * eps(eltype(T)))
    if size(r) == (2,2)
        # Transpose is overloaded for many of our types, so we do it explicitly:
        r_trans = @SMatrix [conj(r[1,1])  conj(r[2,1]);
                            conj(r[1,2])  conj(r[2,2])]
        d = vecnorm((r * r_trans) - eye(SMatrix{2,2}))
    elseif size(r) == (3,3)
        r_trans = @SMatrix [conj(r[1,1])  conj(r[2,1])  conj(r[3,1]);
                            conj(r[1,2])  conj(r[2,2])  conj(r[2,3]);
                            conj(r[1,3])  conj(r[2,3])  conj(r[3,3])]
        d = vecnorm((r * r_trans) - eye(SMatrix{3,3}))
    else
        return false
    end

    return d < tol
end


# A simplification and specialization of the Base.showarray() function makes
# everything sensible at the REPL.
function Base.showarray(io::IO, X::Rotation, repr::Bool = true; header = true)
    if !haskey(io, :compact)
        io = IOContext(io, compact=true)
    end
    if repr
        if isa(X, RotMatrix)
            Base.print_matrix_repr(io, X)
        else
            print(io, typeof(X).name.name)
            n_fields = length(fieldnames(typeof(X)))
            print(io, "(")
            for i = 1:n_fields
                print(io, getfield(X, i))
                if i < n_fields
                    print(io, ", ")
                end
            end
            print(io, ")")
        end
    else
        if header
            print(io, summary(X))
            if !isa(X, RotMatrix)
                n_fields = length(fieldnames(typeof(X)))
                print(io, "(")
                for i = 1:n_fields
                    print(io, getfield(X, i))
                    if i < n_fields
                        print(io, ", ")
                    end
                end
                print(io, ")")
            end
            println(io, ":")
        end
        punct = (" ", "  ", "")
        Base.print_matrix(io, X, punct...)
    end
end

# Removes module name from output, to match other types
function Base.summary{T,N}(r::Rotation{N,T})
    "$N×$N $(typeof(r).name.name){$(eltype(r))}"
end
