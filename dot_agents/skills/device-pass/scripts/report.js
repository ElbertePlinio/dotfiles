const imageData = document.getElementById("images");
if (imageData) {
  const urls = {};
  for (const [digest, image] of Object.entries(
    JSON.parse(imageData.textContent),
  )) {
    const binary = atob(image.data);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    urls[digest] = URL.createObjectURL(new Blob([bytes], { type: image.mime }));
  }
  imageData.remove();
  document.querySelectorAll("img[data-img]").forEach((img) => {
    if (urls[img.dataset.img]) img.src = urls[img.dataset.img];
  });
}

const zoom = document.getElementById("zoom");
const zoomValue = document.getElementById("zoom-value");
zoom.addEventListener("input", () => {
  document.documentElement.style.setProperty("--zoom", zoom.value / 100);
  zoomValue.textContent = `${zoom.value}%`;
});

document.querySelectorAll(".overlay input").forEach((slider) => {
  slider.addEventListener("input", () => {
    slider.closest(".overlay").querySelector(".top").style.opacity =
      slider.value / 100;
  });
});

const dialog = document.getElementById("viewer");
const opens = [...document.querySelectorAll("button.open")];
let current = 0;
function show(index) {
  current = index;
  const source = opens[index].querySelector("img");
  const img = document.getElementById("viewer-image");
  img.src = source.src;
  img.alt = source.alt;
  document.getElementById("viewer-title").textContent = source.alt;
  document.getElementById("position").textContent =
    `${index + 1} / ${opens.length}`;
  document.getElementById("previous").disabled = index === 0;
  document.getElementById("next").disabled = index === opens.length - 1;
}
opens.forEach((button, index) => {
  button.addEventListener("click", () => {
    show(index);
    dialog.showModal();
  });
});
document.getElementById("previous").addEventListener("click", () => {
  if (current > 0) show(current - 1);
});
document.getElementById("next").addEventListener("click", () => {
  if (current < opens.length - 1) show(current + 1);
});
document.getElementById("close").addEventListener("click", () => dialog.close());
dialog.addEventListener("click", (event) => {
  if (event.target === dialog) dialog.close();
});
dialog.addEventListener("close", () => opens[current]?.focus());
document.addEventListener("keydown", (event) => {
  if (!dialog.open) return;
  if (event.key === "ArrowLeft" && current > 0) show(current - 1);
  if (event.key === "ArrowRight" && current < opens.length - 1)
    show(current + 1);
});
