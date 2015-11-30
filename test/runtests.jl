
a = addprocs(1)
@everywhere using SimpleFileServer
@everywhere using Logging
@everywhere @Logging.configure(level=DEBUG)
@everywhere using Base.Test

@spawnat  a[1]  begin
    begin
        mktempdir()do d1
            SimpleFileServer.Server.start(8080,d1, ()->())
        end
    end
end
Profile.clear()
function test_setup(f::Function)
    mktempdir() do d2
        fn = "file"
        to = "$d2/file"

        # Test with one page
        name, handle = mktemp(d2)
        orig = Mmap.mmap(handle, Array{UInt8, 1}, 1000)
        rand!(orig)
        Mmap.sync!(orig)
        client = SimpleFileServer.Client.make("localhost", 8080)
        f(fn, to, orig, name, client)
    end
end

test_setup() do fn, to, orig, name,client
    f = SimpleFileServer.Client.upload(client, fn, orig )
    @info "Upload Completed using mmap"
    @debug f
    dl = SimpleFileServer.Client.download(client, fn, to)
    @test orig == dl
    @info "Full Download Correct"
    dl = SimpleFileServer.Client.download(client, fn, to, 11, 9)
    @test orig[10:20] == dl
    @info "Partial Download Correct"
    @debug SimpleFileServer.Client.delete(client, fn)
    rm(to)
    @info "File Deleted"
    err = @test_throws Base.UVError SimpleFileServer.Client.delete(client, fn)
    @info "Double Delete Fails"
    @info err
    err = @test_throws Base.UVError SimpleFileServer.Client.download(client, fn, to)
    @info err
    @info "Missign Download Fails"
    
    f = SimpleFileServer.Client.upload(client, fn, ASCIIString(name))
    @info "Upload Completed using file name, missing download did not re-create file"
    dl = SimpleFileServer.Client.download(client, fn, to)

    @debug SimpleFileServer.Client.delete(client, fn)

end
    # Test with two pages

test_setup() do fn, to, orig, name, client
    f = SimpleFileServer.Client.upload(client, fn, orig )
    @info "Upload Completed using mmap"
    @debug f
    dl = SimpleFileServer.Client.download(client, fn, to)
    @test orig == dl
    @info "Full Download Correct"
    dl = SimpleFileServer.Client.download(client, fn, to, 11, 9)
    @test orig[10:20] == dl
    @info "Partial Download Correct"
    @debug SimpleFileServer.Client.delete(client, fn)
    rm(to)
    @info "File Deleted"
    err = @test_throws Base.UVError SimpleFileServer.Client.delete(client, fn)
    @info "Double Delete Fails"
    @info err
    err = @test_throws Base.UVError SimpleFileServer.Client.download(client, fn, to)
    @info err
    @info "Missign Download Fails"
    
    f = SimpleFileServer.Client.upload(client, fn, ASCIIString(name))
    @info "Upload Completed using file name, missing download did not re-create file"
    dl = SimpleFileServer.Client.download(client, fn, to)
    
end


Profile.print()
