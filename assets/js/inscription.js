const ownerForm =
    document.getElementById("ownerForm");

const subject =
    document.getElementById("subject");

const characterCount =
    document.getElementById("characterCount");

const formMessage =
    document.getElementById("formMessage");


subject.addEventListener("input", () => {

    characterCount.textContent =
        subject.value.length;

});


ownerForm.addEventListener("submit", (event) => {

    event.preventDefault();

    formMessage.textContent =
        "Le formulaire fonctionne. L'enregistrement sécurisé sera activé après la connexion à Supabase.";

});