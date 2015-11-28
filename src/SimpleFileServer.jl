module SimpleFileServer
export File
using Logging
using SHA

@Logging.configure(level=DEBUG)
immutable File
    name::ASCIIString
    hash::ASCIIString
    size::Int64
end
abstract FileCommand

# TODO: is this really safe?
safePath(path::AbstractString)  = path |> expanduser |> abspath
function safePath(f::Function,base::AbstractString, path::AbstractString)
    p = safePath(path)
    if startswith(p, base)
        f(p)
    else
        throw(ErrorException("Unsafe Path $path"))
    end
end

type Download <: FileCommand
    name::ASCIIString
    n_bytes_offset::Nullable{Tuple{Integer,Integer}}
end
type Delete <: FileCommand
    name::ASCIIString
end
type Upload <: FileCommand
    f::File
end
function HandleFileCommand(conn, args::Download, base::AbstractString)
    safePath(base, args.name) do path
        try
            a = if isnull(args.n_bytes_offset)
                    Mmap.mmap(path, Array{UInt8,1})
                else
                    n_bytes, offset = args.n_bytes_offset.value
                    # TODO figure out right way to do this
                    Mmap.mmap(path, Array{UInt8,1})[n_bytes:offset+n_bytes]

                end
            serialize(conn, length(a))
            write(conn, a)
        catch err
            #TODO Don't use this -- what's a better solution thought?
            serialize(conn, -1)
        finally
            flush(conn)
        end
    end
end
function HandleFileCommand(conn, args::Delete, base::AbstractString)
    try
        safePath(base, args.name) do path
            rm(path)
        end
        serialize(conn, Nullable())
    catch err
        @show typeof(err)
        serialize(conn, Nullable(err))
    end
end
function HandleFileCommand(conn, up::Upload, base::AbstractString)
    args = up.f
    safePath(base, args.name) do path
        if length(args.hash) != 64
            throw(ErrorException("Malformed Hash"))
        end
        if isfile(path)
            throw(ErrorException("File Already Exists"))
        end
        open(path, "w+") do f
            a = Mmap.mmap(f, Array{UInt8, 1}, args.size)
            read!(conn, a)
            Mmap.sync!(a)
        end
        if SHA.sha256(open(path)) != args.hash
            rm(path)
            throw(ErrorException("File did not hash properly"))
        end
        serialize(conn,Nullable{ErrorException}())
    end
end

function start(port::Int64, base::AbstractString, setup::Function)
    @info "Starting SimpleFileServer on port $port in path $base"
    server = listen(port)
    setup()
    while  true
        conn = accept(server)
        @debug "Got a Connection"
        @async begin
            while true
                try
                    args = deserialize(conn)::FileCommand
                    @debug args
                    HandleFileCommand(conn, args, base)
                catch err
                    @debug err
                    # serialize(conn, Nullable(err))
                    close(conn)
                    break
                finally 
                    close(conn)
                end
            end
        end
    end
end

function main()
    port = parse(Int64, ARGS[1])
    base = safePath(args[2])
    
    start(port, base)
end

module Client
using SHA
using SimpleFileServer: Upload, Download, Delete, File
export make, download, upload, delete
immutable t
    host::AbstractString
    port::Int64
end
@inline function make(host::AbstractString, port::Int64)
    t(host, port)
end
@inline function t_connect(c::t)
    connect(c.host, c.port)
end
function download(client::t, name::ASCIIString, to::ASCIIString, n_bytes_offset::Nullable{Tuple{Int64, Int64}})
    conn = t_connect(client)
    serialize(conn, Download(name,n_bytes_offset))
    flush(conn)
    s =deserialize(conn)
    if s == -1
        throw(Base.UVError("Remote Server $(client.host):$(client.port)", Base.UV_ENOENT))
    elseif s == 0
        touch(to)
        Array(UInt8, 0)
    else
        m = Mmap.mmap(open(to, "w+"), Array{UInt8, 1}, s)
        readbytes!( conn, m, typemax(Int64))
        m
    end
end
download(client::t, name::ASCIIString, to::ASCIIString, n_bytes::Integer, offset::Integer)= download(client, name, to, Nullable((n_bytes,offset)))
download(client::t, name::ASCIIString, to::ASCIIString)= download(client, name, to, Nullable{Tuple{Int64, Int64}}())
function upload(c::t, name::ASCIIString,m::Array{UInt8, 1})
    f = File(name, SHA.sha256(m), length(m))
    upload(c, f, m)
    f
end
function upload(c::t, f::File, m::Array{UInt8,1})
    conn = t_connect(c)
    serialize(conn, Upload(f))
    write(conn, m)
    flush(conn)
    m_err = deserialize(conn)
    if !isnull(m_err)
        throw(m_err.value)
    end
end

function upload(c::t, name::ASCIIString,m::Array{UInt8, 1})
    f = File(name, SHA.sha256(m), length(m))
    upload(c, f, m)
    f
end
function upload(c::t, name::ASCIIString, path::ASCIIString)
    open(path, "r+") do f
        m = Mmap.mmap(f, Array{UInt8,1})
        upload(c, name, m)
    end
end
function delete(c::t, name::ASCIIString)
    conn = t_connect(c)
    serialize(conn, Delete(name))
    flush(conn)
    m_err = deserialize(conn)
    if !isnull(m_err)
        throw(m_err.value)
    end
end
end
end # module

