using SimpleFileServer
using Logging
@Logging.configure(level=DEBUG)
using Base.Test

# write your own tests here
@test 1 == 1

mktempdir()do d
    testdata = "TESTDATA"
    orig = Mmap.mmap(testdata, Array{UInt8, 1})
    fn = "$d/file"
    to = "$d/file2"
    @async SimpleFileServer.start(8080,d, ()->())
    client = SimpleFileServer.Client.make("localhost", 8080)
    f = SimpleFileServer.Client.upload(client, fn, testdata)
    @info f
    dl = SimpleFileServer.Client.download(client, fn, to)
    @test orig == dl
    dl = SimpleFileServer.Client.download(client, fn, to, 10, 10)
    @test orig[10:20] == dl
    @info SimpleFileServer.Client.delete(client, fn)

    err = @test_throws Base.UVError SimpleFileServer.Client.delete(client, fn)
    @info err
    
    
    err = @test_throws Base.UVError SimpleFileServer.Client.download(client, fn, to)
    @info err
    

    
end
