# Test fixtures — attribution

The `.jpg` photos in this directory are used as test inputs for
`ShowcaseThumbnailTests.swift` (real-photo subjects in showcase
thumbnails) and `SmartObjectIntegrationTests.swift` (raster
placement workflow).

## Source

All photos retrieved from [Lorem Picsum](https://picsum.photos), a
service that serves curated photos from [Unsplash](https://unsplash.com).

| Local file   | Source                                 | Subject          |
|--------------|----------------------------------------|------------------|
| `sunset.jpg` | `picsum.photos/seed/face/540/720`      | Beach at sunset  |
| `cafe.jpg`   | `picsum.photos/seed/creator/540/720`   | Urban cafe       |
| `clouds.jpg` | `picsum.photos/seed/tech/540/720`      | Bird in clouds   |

## License

Photos served by Lorem Picsum are sourced from Unsplash under the
[Unsplash License](https://unsplash.com/license):

> Unsplash photos are made to be used freely. Our license reflects that.
>
> - All photos can be downloaded and used for free
> - Commercial and non-commercial purposes
> - No permission needed (though attribution is appreciated)

These fixtures are committed to the repo so tests run reproducibly
without network access.
