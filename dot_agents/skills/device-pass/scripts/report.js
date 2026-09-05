const dialog = document.getElementById("viewer");
const shots = [...document.querySelectorAll(".shot a")];
let current = 0;
let mode = "all";
function visibleShots() {
  return shots.filter(
    (shot) =>
      !shot.closest(".scenario").hidden && !shot.closest(".shot").hidden,
  );
}
function updateViewer() {
  const shot = shots[current];
  const img = document.getElementById("viewer-image");
  img.src = shot.href;
  img.alt = shot.querySelector("img").alt;
  document.getElementById("viewer-title").textContent = img.alt;
  document.getElementById("original").href = shot.href;
  const visible = visibleShots();
  const index = visible.indexOf(shot);
  document.getElementById("position").textContent =
    `${index + 1} / ${visible.length} · ← → to browse`;
  document.getElementById("previous").disabled = index === 0;
  document.getElementById("next").disabled = index === visible.length - 1;
  document.querySelector(".viewer-stage").classList.remove("zoom");
  document.getElementById("zoom").setAttribute("aria-pressed", "false");
  document.getElementById("zoom").textContent = "Actual size";
}
function move(delta) {
  const visible = visibleShots();
  const index = visible.indexOf(shots[current]) + delta;
  if (index < 0 || index >= visible.length) return;
  current = shots.indexOf(visible[index]);
  updateViewer();
}
shots.forEach((shot, index) =>
  shot.addEventListener("click", (event) => {
    event.preventDefault();
    current = index;
    updateViewer();
    dialog.showModal();
  }),
);
document
  .getElementById("close")
  .addEventListener("click", () => dialog.close());
document.getElementById("previous").addEventListener("click", () => move(-1));
document.getElementById("next").addEventListener("click", () => move(1));
dialog.addEventListener("keydown", (event) => {
  if (event.key === "ArrowRight") move(1);
  if (event.key === "ArrowLeft") move(-1);
});
document.getElementById("zoom").addEventListener("click", (event) => {
  const zoom = document.querySelector(".viewer-stage").classList.toggle("zoom");
  event.currentTarget.setAttribute("aria-pressed", String(zoom));
  event.currentTarget.textContent = zoom ? "Fit to view" : "Actual size";
});
function filterScenario(section, query) {
  const matchesMode = mode === "all" || section.dataset.mode === mode;
  let count = 0;
  section.querySelectorAll(".shot").forEach((shot) => {
    const match = shot.textContent.toLowerCase().includes(query);
    shot.hidden = !match;
    if (match) count++;
  });
  section.hidden = !matchesMode || count === 0;
  return section.hidden ? 0 : count;
}
function filter() {
  const query = document.getElementById("search").value.toLowerCase().trim();
  let count = 0;
  document
    .querySelectorAll(".scenario")
    .forEach((section) => (count += filterScenario(section, query)));
  document.getElementById("result-count").textContent = `${count} captures`;
  document.getElementById("empty").hidden = count > 0;
}
document.querySelectorAll("[data-filter]").forEach((button) =>
  button.addEventListener("click", () => {
    mode = button.dataset.filter;
    document.querySelectorAll("[data-filter]").forEach((item) => {
      item.classList.toggle("active", item === button);
      item.setAttribute("aria-pressed", String(item === button));
    });
    filter();
  }),
);
document.getElementById("search").addEventListener("input", filter);
