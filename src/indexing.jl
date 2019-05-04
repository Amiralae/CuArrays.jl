import GPUArrays: allowscalar, @allowscalar


## unified memory indexing

# TODO: needs to think about coherency -- otherwise this might crash since it doesn't sync
#       also, this optim would be relevant for CuArray<->Array memcpy as well.

function GPUArrays._getindex(xs::CuArray{T}, i::Integer) where T
  buf = buffer(xs)
  if isa(buf, Mem.UnifiedBuffer)
    ptr = convert(Ptr{T}, buffer(xs))
    unsafe_load(ptr, i)
  else
    val = Array{T}(undef)
    copyto!(val, 1, xs, i, 1)
    val[]
  end
end

function GPUArrays._setindex!(xs::CuArray{T}, v::T, i::Integer) where T
  buf = buffer(xs)
  if isa(buf, Mem.UnifiedBuffer)
    ptr = convert(Ptr{T}, buffer(xs))
    unsafe_store!(ptr, v, i)
  else
    copyto!(xs, i, T[v], 1, 1)
  end
end


## logical indexing

Base.getindex(xs::CuArray, bools::AbstractArray{Bool}) = getindex(xs, CuArray(bools))

function Base.getindex(xs::CuArray{T}, bools::CuArray{Bool}) where {T}
  bools = reshape(bools, prod(size(bools)))
  indices = cumsum(bools)  # unique indices for elements that are true

  n = GPUArrays._getindex(indices, length(indices))  # number that are true
  ys = CuArray{T}(undef, n)

  if n > 0
    num_threads = min(n, 256)
    num_blocks = ceil(Int, length(indices) / num_threads)

    function kernel(ys::CuDeviceArray{T}, xs::CuDeviceArray{T}, bools, indices)
        i = threadIdx().x + (blockIdx().x - 1) * blockDim().x

        if i <= length(xs) && bools[i]
            b = indices[i]   # new position
            ys[b] = xs[i]

        end

        return
    end

    @cuda blocks=num_blocks threads=num_threads kernel(ys, xs, bools, indices)
  end

  return ys
end
