Project setup. Create or extend the Remotion project with Bun, installing dependencies project-locally and never globally. Discover the installed Remotion version rather than pinning blindly, and use Bun for all project scripts in new standalone projects.

Official skills. Some projects carry official Remotion agent skills locally. If the current project has them, consult them there for API specifics after checking that their license permits that use. Do not copy their text into this skill or other projects; the workflow in this skill is original.

Editing. Build the composition from the real footage and drive timing from the pointer and click metadata: zoom into the region under the pointer when a click lands, blur anything that must not be readable, and cut on real action boundaries. Captions transcribe what is actually said or state what is actually shown; no invented claims, metrics, or outcomes. If footage is sped up, keep it recognizable as real interaction and note the speedup in the manifest.

Rendering. Render a 16:9 master at the composition's resolution and frame rate with the Remotion CLI through Bun. Produce the 4:5 mobile reframe by recomposing the scene for the narrower frame, cropping and scaling deliberately rather than squeezing the master. Render a thumbnail still from a chosen frame.

Validation. Run ffprobe on every output for codec, frame rate, and duration, extract frames at key moments and inspect them, and decode or play the file end to end to confirm real playback. A successful render or a passing test is not visual proof; look at the frames and the played video. Compare the mobile reframe and thumbnail against the master for framing and legibility.

Deliverables. Keep the outputs together with the manifest: the 16:9 master, the 4:5 reframe, the thumbnail, the Remotion source project, and the capture manifest from the capture reference. Evidence and renders stay outside application repositories unless the project states otherwise, and nothing is uploaded or published without the user's submission.
