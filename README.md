# video-frame-processor

### Frame Hanlder
VideoConverter will help you to process the frame of video in your phone. You can add function at

```
converter?.frameProcess = { (sampleBuffer) in
    // do your work here
}
```

You can process frame of the type [CMSampleBuffer](https://developer.apple.com/documentation/coremedia/cmsamplebuffer-u71).

### Angle
If you want to enter angle and reuse it, call ```AFPProfile.angle```.
