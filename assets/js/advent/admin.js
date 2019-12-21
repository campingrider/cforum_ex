const hideOrShowAuthor = ev => {
  authorElement.closest(".cf-cgroup").hidden = !!ev.target.value;
};

const hideOrShowUser = ev => {
  userElement.closest(".cf-cgroup").hidden = !!ev.target.value;
};

const userElement = document.querySelector("[name='day[user_id]']");
const authorElement = document.getElementById("day_author");

if (userElement && authorElement) {
  userElement.addEventListener("change", hideOrShowAuthor);
  authorElement.addEventListener("change", hideOrShowUser);
}
